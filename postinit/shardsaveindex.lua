-- Patch vanilla ShardSaveIndex slot bookkeeping so active world switches keep
-- their saved slot reserved and recoverable.

GLOBAL.setfenv(1, GLOBAL)

local function SlotHasActiveWorldSwitchSidecar(slot)
    return ShardWorldIndex:HasActiveSidecar(slot)
end

local function ReadActiveWorldSwitchSidecar(slot)
    return ShardWorldIndex:ReadActiveSidecar(slot)
end

local function RecoverWorldSwitchSlot(slot, state)
    if slot == nil or state == nil then
        return false
    end

    local shard_index = ShardSaveGameIndex ~= nil and ShardSaveGameIndex:GetShardIndex(slot, "Master") or nil
    if shard_index == nil then
        shard_index = ShardIndex()
        shard_index:LoadShardInSlot(slot, "Master")
        if not shard_index:IsValid() then
            shard_index.preserve_world_switch_sidecar = true
            shard_index:NewShardInSlot(slot, "Master")
            shard_index.preserve_world_switch_sidecar = nil
        end
        ShardSaveGameIndex.slot_cache[slot] = ShardSaveGameIndex.slot_cache[slot] or {}
        ShardSaveGameIndex.slot_cache[slot].Master = shard_index
    end

    if shard_index:GetSession() == nil or shard_index:GetSession() == "" then
        shard_index.worldindex:SwitchIndexToStoredWorld(state)
        shard_index:Save()
    end
    return true
end

local function RefreshWorldSwitchSlots(index)
    if index == nil or TheSim == nil then
        return
    end

    index.slots = index.slots or {}
    for slot = 1, NUM_DST_SAVE_SLOTS do
        local state = ReadActiveWorldSwitchSidecar(slot)
        if state ~= nil and RecoverWorldSwitchSlot(slot, state) then
            index.slots[slot] = index.slots[slot] or false
        end
    end
end

local _IsSlotEmpty = ShardSaveIndex.IsSlotEmpty
function ShardSaveIndex:IsSlotEmpty(slot)
    if SlotHasActiveWorldSwitchSidecar(slot) then
        return false
    end
    return _IsSlotEmpty(self, slot)
end

local _GetNextNewSlot = ShardSaveIndex.GetNextNewSlot
function ShardSaveIndex:GetNextNewSlot(force_slot_type)
    if force_slot_type == "cloud" or (force_slot_type ~= "local" and Profile:GetDefaultCloudSaves()) then
        return _GetNextNewSlot(self, force_slot_type)
    end

    local i = 1
    while true do
        if (self.failed_slot_conversions or {})[i] == nil and
            not SlotHasActiveWorldSwitchSidecar(i) and
            (self.slots[i] == nil or self:IsSlotEmpty(i)) then
            return i
        end
        i = i + 1
    end
end

local _Load = ShardSaveIndex.Load
function ShardSaveIndex:Load(callback)
    _Load(self, function(...)
        local args = { ... }
        RefreshWorldSwitchSlots(self)
        if callback ~= nil then
            callback(unpack(args))
        end
    end)
end

local _GetValidSlots = ShardSaveIndex.GetValidSlots
function ShardSaveIndex:GetValidSlots()
    RefreshWorldSwitchSlots(self)
    return _GetValidSlots(self)
end

local _Save = ShardSaveIndex.Save
function ShardSaveIndex:Save(callback)
    RefreshWorldSwitchSlots(self)
    return _Save(self, callback)
end
