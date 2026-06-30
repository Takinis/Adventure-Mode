GLOBAL.setfenv(1, GLOBAL)

local function SlotHasActiveAdventureSidecar(slot)
    if slot == nil or TheSim == nil then
        return false
    end

    local has_active_adventure = false
    TheSim:GetPersistentStringInClusterSlot(slot, "Master", "shardindex_adventure", function(load_success, str)
        if load_success and str ~= nil and #str > 0 then
            local success, state = RunInSandboxSafe(str)
            has_active_adventure = success and
                type(state) == "table" and
                state.active == true and
                type(state.main) == "table" and
                state.main.session_id ~= nil and
                state.main.session_id ~= ""
        end
    end)
    return has_active_adventure
end

local function ReadActiveAdventureSidecar(slot)
    if slot == nil or TheSim == nil then
        return nil
    end

    local adventure_state = nil
    TheSim:GetPersistentStringInClusterSlot(slot, "Master", "shardindex_adventure", function(load_success, str)
        if load_success and str ~= nil and #str > 0 then
            local success, state = RunInSandboxSafe(str)
            if success and
                type(state) == "table" and
                state.active == true and
                type(state.main) == "table" and
                state.main.session_id ~= nil and
                state.main.session_id ~= "" then
                adventure_state = state
            end
        end
    end)
    return adventure_state
end

local function RecoverAdventureSlot(slot, state)
    if slot == nil or state == nil then
        return false
    end

    local shard_index = ShardSaveGameIndex ~= nil and ShardSaveGameIndex:GetShardIndex(slot, "Master") or nil
    if shard_index == nil then
        shard_index = ShardIndex()
        shard_index:LoadShardInSlot(slot, "Master")
        if not shard_index:IsValid() then
            shard_index.preserve_adventure_sidecar = true
            shard_index:NewShardInSlot(slot, "Master")
            shard_index.preserve_adventure_sidecar = nil
        end
        ShardSaveGameIndex.slot_cache[slot] = ShardSaveGameIndex.slot_cache[slot] or {}
        ShardSaveGameIndex.slot_cache[slot].Master = shard_index
    end

    if shard_index:GetSession() == nil or shard_index:GetSession() == "" then
        ShardWorldIndex:SwitchIndexToExistingWorld(shard_index, state.main)
        shard_index:Save()
    end
    return true
end

local function RefreshAdventureSlots(index)
    if index == nil or TheSim == nil then
        return
    end

    index.slots = index.slots or {}
    for slot = 1, NUM_DST_SAVE_SLOTS do
        local state = ReadActiveAdventureSidecar(slot)
        if state ~= nil and RecoverAdventureSlot(slot, state) then
            index.slots[slot] = index.slots[slot] or false
        end
    end
end

local _IsSlotEmpty = ShardSaveIndex.IsSlotEmpty
function ShardSaveIndex:IsSlotEmpty(slot)
    if SlotHasActiveAdventureSidecar(slot) then
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
            not SlotHasActiveAdventureSidecar(i) and
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
        RefreshAdventureSlots(self)
        if callback ~= nil then
            callback(unpack(args))
        end
    end)
end

local _GetValidSlots = ShardSaveIndex.GetValidSlots
function ShardSaveIndex:GetValidSlots()
    RefreshAdventureSlots(self)
    return _GetValidSlots(self)
end

local _Save = ShardSaveIndex.Save
function ShardSaveIndex:Save(callback)
    RefreshAdventureSlots(self)
    return _Save(self, callback)
end
