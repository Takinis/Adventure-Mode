-- Patch vanilla ShardIndex lifecycle methods so world switching can
-- keep sidecar state in sync. Adventure Mode is one consumer of this layer.

GLOBAL.setfenv(1, GLOBAL)

local _ctor = ShardIndex._ctor
function ShardIndex._ctor(self, ...)
    _ctor(self, ...)
    self.worldindex = ShardWorldIndex(self)
    self.adventure = ShardAdventureIndex(self)
end

local _Load = ShardIndex.Load
function ShardIndex:Load(callback)
    _Load(self, function(...)
        local args = { ... }
        self.worldindex:LoadSidecar(function()
            if callback ~= nil then
                callback(unpack(args))
            end
        end)
    end)
end

local _LoadShardInSlot = ShardIndex.LoadShardInSlot
function ShardIndex:LoadShardInSlot(slot, shard, callback)
    _LoadShardInSlot(self, slot, shard, function(...)
        local args = { ... }
        self.worldindex:LoadSidecar(function()
            if callback ~= nil then
                callback(unpack(args))
            end
        end)
    end)
end

local _NewShardInSlot = ShardIndex.NewShardInSlot
function ShardIndex:NewShardInSlot(slot, shard)
    _NewShardInSlot(self, slot, shard)
    if not self.preserve_world_switch_sidecar then
        self.worldindex:ClearSidecar()
    end
end

local _IsEmpty = ShardIndex.IsEmpty
function ShardIndex:IsEmpty()
    if self.worldindex:NeedsGenerationOnLoad() then
        return true
    end
    if self.worldindex:ReservesSlot() then
        return false
    end
    return _IsEmpty(self)
end

local _Delete = ShardIndex.Delete
function ShardIndex:Delete(cb, save_options)
    if self.worldindex:PreservePendingGenerationOnDelete(save_options, cb) then
        return
    end

    self.worldindex:PrepareDelete(save_options, function()
        _Delete(self, cb, save_options)
    end)
end

local _SetServerShardData = ShardIndex.SetServerShardData
function ShardIndex:SetServerShardData(customoptions, serverdata, onsavedcb)
    local function set_server_shard_data()
        _SetServerShardData(self, customoptions, serverdata, onsavedcb)
    end

    if not self.worldindex:PrepareSetServerShardData(set_server_shard_data) then
        set_server_shard_data()
    end
end

GLOBAL_SAVEDATA = nil

local _OnGenerateNewWorld = ShardIndex.OnGenerateNewWorld
function ShardIndex:OnGenerateNewWorld(savedata, metadataStr, session_identifier, cb)
    print("ShardIndex:OnGenerateNewWorld")
    local success, world_table
    world_table = savedata
    if type(savedata) == "string" then
        success, world_table = RunInSandbox(savedata)
    end
    GLOBAL_SAVEDATA = world_table

    savedata, metadataStr = self.worldindex:BeforeGenerateNewWorld(savedata, metadataStr, session_identifier)
    _OnGenerateNewWorld(self, savedata, metadataStr, session_identifier, function(...)
        local args = { ... }
        self.worldindex:AfterGenerateNewWorld(savedata, session_identifier, function()
            if cb ~= nil then
                cb(unpack(args))
            end
        end)
    end)
end

local _GetSaveData = ShardIndex.GetSaveData
function ShardIndex:GetSaveData(_callback, ...)
    print("ShardIndex:GetSaveData")
    local function callback(savedata, ...)
        GLOBAL_SAVEDATA = savedata
        return _callback(savedata, ...)
    end
    return _GetSaveData(self, callback, ...)
end

local _GetSaveDataFile = ShardIndex.GetSaveDataFile
function ShardIndex:GetSaveDataFile(file, _callback, ...)
    print("ShardIndex:GetSaveDataFile")
    local function callback(savedata, ...)
        GLOBAL_SAVEDATA = savedata
        return _callback(savedata, ...)
    end
    return _GetSaveDataFile(self, file, callback, ...)
end
