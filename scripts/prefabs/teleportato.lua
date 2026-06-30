local assets = {
	Asset("ANIM", "anim/teleportato.zip"),
	Asset("ANIM", "anim/teleportato_build.zip"),
	Asset("ANIM", "anim/teleportato_adventure_build.zip"),
	Asset("ANIM", "anim/teleportato_adventure_parts_build.zip"),
}

local prefabs = {
	"ash",
	"teleportato_player_container",
}

local Parts = {
	teleportato_ring = false,
	teleportato_crank = false,
	teleportato_box = false,
	teleportato_potato = false,
}

local Part_Symbols = {
	teleportato_ring = "RING",
	teleportato_crank = "CRANK",
	teleportato_box = "BOX",
	teleportato_potato = "POTATO",
}

local Part_Order = {
	"teleportato_ring",
	"teleportato_crank",
	"teleportato_box",
	"teleportato_potato",
}

local PART_COUNT = 4
local TELEPORTATO_SLOT_ORDER = { 1, 2, 3, 4 }

local CheckNextLevelSure

local function CountParts(inst)
	local parts_count = 0
	for _, found in pairs(inst.Parts) do
		if found then
			parts_count = parts_count + 1
		end
	end
	return parts_count
end

local function IsValidUserId(userid)
	return userid ~= nil and userid ~= ""
end

local function BuildSlotRecordsFromContainer(container)
	if container == nil or not container:IsValid() or container.components.container == nil then
		return nil
	end

	local out = {}
	local has_any = false
	for _, slot in ipairs(TELEPORTATO_SLOT_ORDER) do
		local item = container.components.container:GetItemInSlot(slot)
		if item ~= nil then
			out[slot] = item:GetSaveRecord()
			has_any = true
		end
	end

	return has_any and out or nil
end

local function CopySlotRecords(records)
	if type(records) ~= "table" then
		return nil
	end

	local out = {}
	local has_any = false
	for _, slot in ipairs(TELEPORTATO_SLOT_ORDER) do
		if type(records[slot]) == "table" then
			out[slot] = deepcopy(records[slot])
			has_any = true
		end
	end

	return has_any and out or nil
end

local function SavePlayerContainerToStore(inst, userid, container)
	if not IsValidUserId(userid) then
		return
	end

	inst._playerstores = inst._playerstores or {}
	inst._playerstores[userid] = BuildSlotRecordsFromContainer(container)
end

local function LoadSlotRecordsIntoContainer(container, records)
	if container == nil or container.components.container == nil or type(records) ~= "table" then
		return
	end

	for _, slot in ipairs(TELEPORTATO_SLOT_ORDER) do
		local record = records[slot]
		if type(record) == "table" then
			local item = SpawnSaveRecord(record)
			if item ~= nil then
				container.components.container:GiveItem(item, slot)
			end
		end
	end
end

local function TrackPlayerContainer(inst, userid, container)
	inst._playercontainers = inst._playercontainers or {}
	inst._playercontainers[userid] = container
	inst:ListenForEvent("onremove", function()
		if inst._playercontainers ~= nil and inst._playercontainers[userid] == container then
			inst._playercontainers[userid] = nil
		end
	end, container)
end

local function GetPlayerContainer(inst, userid, create)
	if not IsValidUserId(userid) then
		return nil
	end

	inst._playercontainers = inst._playercontainers or {}
	local container = inst._playercontainers[userid]
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

	local x, y, z = inst.Transform:GetWorldPosition()
	container.Transform:SetPosition(x, y, z)
	container._userid = userid
	container._base = inst
	container._teleportato_base:set(inst)
	LoadSlotRecordsIntoContainer(container, inst._playerstores ~= nil and inst._playerstores[userid] or nil)
	TrackPlayerContainer(inst, userid, container)

	return container
end

local function GetSlotRecordsForUser(inst, userid)
	local container = GetPlayerContainer(inst, userid, false)
	if container ~= nil then
		local records = BuildSlotRecordsFromContainer(container)
		inst._playerstores = inst._playerstores or {}
		inst._playerstores[userid] = records
		return records
	end

	return CopySlotRecords(inst._playerstores ~= nil and inst._playerstores[userid] or nil)
end

local function ClosePlayerContainers(inst)
	for userid, container in pairs(inst._playercontainers or {}) do
		if container ~= nil and container:IsValid() and container.components.container ~= nil then
			SavePlayerContainerToStore(inst, userid, container)
			container.components.container:Close()
		end
	end
end

local function RemovePlayerContainers(inst)
	local containers = {}
	for userid, container in pairs(inst._playercontainers or {}) do
		table.insert(containers, { userid = userid, container = container })
	end

	for _, data in ipairs(containers) do
		local container = data.container
		if container ~= nil and container:IsValid() then
			SavePlayerContainerToStore(inst, data.userid, container)
			container:Remove()
		end
	end
	inst._playercontainers = {}
end

local function BuildPlayerStoreSaveData(inst)
	local data = {}
	local userids = {}

	for userid in pairs(inst._playerstores or {}) do
		userids[userid] = true
	end
	for userid in pairs(inst._playercontainers or {}) do
		userids[userid] = true
	end

	for userid in pairs(userids) do
		local records = GetSlotRecordsForUser(inst, userid)
		if records ~= nil then
			data[userid] = records
		end
	end

	return next(data) ~= nil and data or nil
end

local function LoadPlayerStoreSaveData(inst, data)
	inst._playerstores = {}
	if type(data) ~= "table" then
		return
	end

	for userid, store in pairs(data) do
		if type(userid) == "string" then
			inst._playerstores[userid] = CopySlotRecords(store)
		end
	end
end

local function FilterInventoryDataForTeleportato(record, slot_records)
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

	for index, slot in ipairs(TELEPORTATO_SLOT_ORDER) do
		local item_record = slot_records ~= nil and slot_records[slot] or nil
		if type(item_record) == "table" then
			out.data.inventory.items[index] = deepcopy(item_record)
		end
	end

	return out
end

local function FilterSessionForTeleportato(inst, session)
	if session == nil or not IsValidUserId(session.userid) then
		return session
	end

	local store = GetSlotRecordsForUser(inst, session.userid)
	if store == nil then
		return session
	end

	local success, record = RunInSandboxSafe(session.data or "")
	if not success or type(record) ~= "table" then
		return session
	end

	local out = deepcopy(session)
	out.data = DataDumper(FilterInventoryDataForTeleportato(record, store), nil, BRANCH ~= "dev")
	return out
end

local function BuildAdventurePlayerSessions(inst)
	local sessions = {}
	local seen = {}
	if AllPlayers == nil then
		AllPlayers = {}
	end

	for _, player in ipairs(AllPlayers) do
		if IsValidUserId(player.userid) and player.prefab ~= nil then
			local record = player:GetSaveRecord()
			local store = GetSlotRecordsForUser(inst, player.userid)
			record = FilterInventoryDataForTeleportato(record, store)
			table.insert(sessions, {
				userid = player.userid,
				prefab = player.prefab,
				data = DataDumper(record, nil, BRANCH ~= "dev"),
				metadata = DataDumper({ character = player.prefab }, nil, BRANCH ~= "dev"),
				mode = "full",
			})
			seen[player.userid] = true
		end
	end

	local state = ShardGameIndex.adventure:GetState()
	if state ~= nil and state.adventure_player_sessions ~= nil then
		for _, session in ipairs(state.adventure_player_sessions) do
			if session.userid ~= nil and session.userid ~= "" and not seen[session.userid] then
				table.insert(sessions, FilterSessionForTeleportato(inst, session))
			end
		end
	end

	return sessions
end

local function EncodeParts(inst)
	local bits = 0
	for index, part in ipairs(Part_Order) do
		if inst.Parts[part] then
			bits = bits + 2 ^ (index - 1)
		end
	end
	return bits
end

local function DecodeParts(inst, bits)
	for index, part in ipairs(Part_Order) do
		local flag = 2 ^ (index - 1)
		inst.Parts[part] = bits ~= nil and bits % (flag * 2) >= flag or false
	end
end

local function RefreshPartSymbols(inst)
	for part, symbol in pairs(Part_Symbols) do
		if inst.Parts[part] then
			inst.AnimState:Show(symbol)
		else
			inst.AnimState:Hide(symbol)
		end
	end
end

local function SyncPartNetvar(inst)
	if TheWorld.ismastersim then
		inst._parts:set(EncodeParts(inst))
	end
end

local function IsMasterAdventureShard()
	return ShardGameIndex.adventure:IsMasterShard()
end

local function SecondaryShardHasPlayers()
	return TheWorld ~= nil and TheWorld.GetSecondaryShardPlayerCount ~= nil and
		TheWorld:GetSecondaryShardPlayerCount() > 0
end

local function DenyTeleportato(doer, message)
	if doer ~= nil and doer.userid ~= nil then
		SendModRPCToClient(GetClientModRPC("AdventureMode", "TeleportatoDenied"), doer.userid, message)
	end
end

local function AreAllPlayersNearby(inst)
	if AllPlayers == nil then
		return false
	end

	for _, player in ipairs(AllPlayers) do
		if player.userid ~= nil and player.userid ~= "" and
			player.components.health ~= nil and not player.components.health:IsDead() and
			not player:IsNear(inst, 10) then
			return false
		end
	end

	return true
end

local function TransitionToNextLevel(inst, doer)
	if not TheWorld:IsAdventureActive() then
		return false
	end

	if CountParts(inst) < PART_COUNT then
		return false
	end

	if not IsMasterAdventureShard() then
		DenyTeleportato(doer, "Only the Master world can unlock the next chapter.")
		return false
	end

	if inst._activating then
		return false
	end

	if SecondaryShardHasPlayers() then
		DenyTeleportato(doer, "Everyone must return from the Caves first.")
		return false
	end

	if not AreAllPlayersNearby(inst) then
		DenyTeleportato(doer)
		return false
	end

	ClosePlayerContainers(inst)

	local player_sessions = BuildAdventurePlayerSessions(inst)

	inst._activating = true

	for _, player in ipairs(AllPlayers) do
		if player.components.health ~= nil and not player.components.health:IsDead() then
			player.is_teleporting = true
			player.sg:GoToState("teleportato_teleport")
		end
	end

	inst:DoTaskInTime(110 * FRAMES, function()
		if inst:IsValid() then
			inst.AnimState:PlayAnimation("laugh", false)
			inst.AnimState:PushAnimation("active_idle", true)
			inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_maxwelllaugh", "teleportato_laugh")
		end
	end)

	TheWorld:DoTaskInTime(5, function()
		inst._activating = false
		ShardGameIndex.adventure:AdvanceShard({ player_sessions = player_sessions })
	end)

	return true
end

local function GetBodyText()
	return "Begin the next Adventure Mode chapter? All living players must stand near the Teleportato."
end

CheckNextLevelSure = function(inst, doer)
	if doer == nil or doer.userid == nil then
		return
	end

	SendModRPCToClient(
		GetClientModRPC("AdventureMode", "Adventure???"),
		doer.userid,
		inst.GUID,
		ZipAndEncodeString({
			title = STRINGS.UI.TELEPORTTITLE,
			body = GetBodyText(),
			yes = STRINGS.UI.TELEPORTYES,
			no = STRINGS.UI.TELEPORTNO,
		})
	)
end

local function EnableTeleportatoActivation(inst)
	if inst.components.activatable ~= nil and not inst._activating then
		inst.components.activatable.inactive = true
	end
end

local function OpenPlayerContainer(inst, doer)
	if doer == nil or not IsValidUserId(doer.userid) then
		EnableTeleportatoActivation(inst)
		return
	end

	local container = GetPlayerContainer(inst, doer.userid, true)
	if container ~= nil and container.components.container ~= nil then
		container.components.container:Open(doer)
	end
	EnableTeleportatoActivation(inst)
end

local function OnActivate(inst, doer)
	if CountParts(inst) < PART_COUNT then
		if inst.components.activatable ~= nil then
			inst.components.activatable.inactive = false
		end
		return
	end

	if not inst.activatedonce then
		inst.activatedonce = true
		inst.AnimState:PlayAnimation("activate", false)
		inst.AnimState:PushAnimation("active_idle", true)
		inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_activate", "teleportato_activate")
		inst.SoundEmitter:KillSound("teleportato_idle")
		inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_activeidle_LP", "teleportato_active_idle")

		inst:DoTaskInTime(40 * FRAMES, function()
			inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_activate_mouth", "teleportato_activatemouth")
		end)

		inst:DoTaskInTime(3.0, function()
			if inst:IsValid() and doer ~= nil and doer:IsValid() then
				OpenPlayerContainer(inst, doer)
			end
		end)
	else
		OpenPlayerContainer(inst, doer)
	end
end

local function GetStatus(inst)
	local parts_count = CountParts(inst)
	if parts_count >= PART_COUNT then
		local rodbase = TheSim:FindFirstEntityWithTag("rodbase")
		if rodbase ~= nil and rodbase.components.lock ~= nil and rodbase.components.lock:IsLocked() then
			return "LOCKED"
		end
		return "ACTIVE"
	elseif parts_count > 0 then
		return "PARTIAL"
	end
end

local function ItemTradeTest(inst, item)
	return item:HasTag("teleportato_part")
end

local function PowerUp(inst)
	if inst._powered then
		return
	end

	inst._powered = true
	inst.AnimState:PlayAnimation("power_on", false)
	inst.AnimState:PushAnimation("idle_on", true)
	inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_powerup", "teleportato_on")
	inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_idle_LP", "teleportato_idle")

	if inst.components.activatable ~= nil then
		inst.components.activatable.inactive = true
	end

	if TheWorld.ismastersim then
		inst._poweredup:set(true)
	end
end

local function OnPowerDirty(inst)
	if inst._poweredup:value() then
		PowerUp(inst)
	end
end

local function OnPartsDirty(inst)
	DecodeParts(inst, inst._parts:value())
	RefreshPartSymbols(inst)
end

local function TestForPowerUp(inst)
	RefreshPartSymbols(inst)
	SyncPartNetvar(inst)

	if CountParts(inst) < PART_COUNT then
		return
	end

	if inst.components.trader ~= nil then
		inst.components.trader:Disable()
	end

	local rodbase = TheSim:FindFirstEntityWithTag("rodbase")
	if rodbase ~= nil and rodbase.components.lock ~= nil and rodbase.components.lock:IsLocked() then
		if not inst._waiting_for_powerup then
			inst._waiting_for_powerup = true
			inst:ListenForEvent("powerup", PowerUp)
		end
		rodbase:PushEvent("ready")
	else
		inst:DoTaskInTime(0.5, PowerUp)
	end
end

local function ItemGet(inst, giver, item)
	if inst.Parts[item.prefab] ~= nil then
		inst.Parts[item.prefab] = true
		inst.SoundEmitter:KillSound("teleportato_addpart")
		inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_addpart", "teleportato_addpart")
		TestForPowerUp(inst)
	end
end

local function OnLoad(inst, data)
	if data ~= nil and data.Parts ~= nil then
		for part, _ in pairs(Part_Symbols) do
			inst.Parts[part] = data.Parts[part] == true
		end
	end

	inst.activatedonce = data ~= nil and data.activatedonce or false
	inst._powered = data ~= nil and data.powered or false
	inst._activating = false
	inst._waiting_for_powerup = false
	inst._playercontainers = {}
	LoadPlayerStoreSaveData(inst, data ~= nil and data.playerstores or nil)

	RefreshPartSymbols(inst)
	SyncPartNetvar(inst)

	if inst._powered then
		if inst.activatedonce then
			inst.AnimState:PlayAnimation("active_idle", true)
			inst.SoundEmitter:KillSound("teleportato_idle")
			inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_activeidle_LP", "teleportato_active_idle")
		else
			inst.AnimState:PlayAnimation("idle_on", true)
			inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_idle_LP", "teleportato_idle")
		end
		if inst.components.activatable ~= nil then
			inst.components.activatable.inactive = true
		end
		if TheWorld.ismastersim then
			inst._poweredup:set(true)
		end
	else
		if inst.components.activatable ~= nil then
			inst.components.activatable.inactive = false
		end
		TestForPowerUp(inst)
	end
end

local function OnSave(inst, data)
	data.Parts = {}
	for part, found in pairs(inst.Parts) do
		data.Parts[part] = found
	end
	data.activatedonce = inst.activatedonce == true
	data.powered = inst._powered == true
	data.playerstores = BuildPlayerStoreSaveData(inst)
end

local function fn()
	local inst = CreateEntity()
	inst.entity:AddTransform()
	inst.entity:AddAnimState()
	inst.entity:AddSoundEmitter()
	inst.entity:AddMiniMapEntity()
	inst.entity:AddNetwork()

	inst.AnimState:SetBank("teleporter")
	inst.AnimState:SetBuild("teleportato_adventure_build")
	inst.AnimState:PlayAnimation("idle_off", true)

	inst:AddTag("teleportato")
	inst:AddTag("trader")

	inst._parts = net_tinybyte(inst.GUID, "teleportato._parts", "teleportatopartsdirty")
	inst._poweredup = net_bool(inst.GUID, "teleportato._poweredup", "teleportatopowerdirty")

	MakeObstaclePhysics(inst, 1.1)

	inst.MiniMapEntity:SetPriority(5)
	inst.MiniMapEntity:SetIcon("teleportato.png")
	inst.MiniMapEntity:SetPriority(1)

	for _, symbol in pairs(Part_Symbols) do
		inst.AnimState:Hide(symbol)
	end

	inst.entity:SetPristine()

	inst.Parts = deepcopy(Parts)

	if not TheWorld.ismastersim then
		inst:ListenForEvent("teleportatopartsdirty", OnPartsDirty)
		inst:ListenForEvent("teleportatopowerdirty", OnPowerDirty)
		inst:DoTaskInTime(0, OnPartsDirty)
		inst:DoTaskInTime(0, OnPowerDirty)
		return inst
	end

	inst._powered = false
	inst._activating = false
	inst._waiting_for_powerup = false
	inst.activatedonce = false
	inst._playercontainers = {}
	inst._playerstores = {}

	inst:AddComponent("inspectable")
	inst.components.inspectable.getstatus = GetStatus
	inst.components.inspectable:RecordViews()

	inst:AddComponent("activatable")
	inst.components.activatable.OnActivate = OnActivate
	inst.components.activatable.inactive = false
	inst.components.activatable.quickaction = true

	inst:AddComponent("trader")
	inst.components.trader:SetAcceptTest(ItemTradeTest)
	inst.components.trader.onaccept = ItemGet

	inst.Adventure = TransitionToNextLevel
	inst.CheckNextLevelSure = CheckNextLevelSure
	inst.OnSave = OnSave
	inst.OnLoad = OnLoad
	inst.OnRemoveEntity = RemovePlayerContainers

	RefreshPartSymbols(inst)
	SyncPartNetvar(inst)

	return inst
end

return Prefab("teleportato_base", fn, assets, prefabs)
