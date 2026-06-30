-- Patch vanilla ShardIndex lifecycle methods so Adventure Mode can keep its
-- sidecar state in sync. Gameplay-facing calls go through ShardGameIndex.adventure.

GLOBAL.setfenv(1, GLOBAL)

local _ctor = ShardIndex._ctor
function ShardIndex._ctor(self, ...)
    _ctor(self, ...)
    self.adventure = ShardAdventureIndex(self)
end

local _Load = ShardIndex.Load
function ShardIndex:Load(callback)
    _Load(self, function(...)
        local args = { ... }
        self.adventure:LoadSidecar(function()
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
        self.adventure:LoadSidecar(function()
            if callback ~= nil then
                callback(unpack(args))
            end
        end)
    end)
end

local _NewShardInSlot = ShardIndex.NewShardInSlot
function ShardIndex:NewShardInSlot(slot, shard)
    _NewShardInSlot(self, slot, shard)
    if not self.preserve_adventure_sidecar then
        self.adventure:ClearSidecar()
    end
end

local _IsEmpty = ShardIndex.IsEmpty
function ShardIndex:IsEmpty()
    if self.adventure ~= nil then
        if self.adventure:NeedsGenerationOnLoad() then
            return true
        end
        if self.adventure:ReservesSlot() then
            return false
        end
    end
    return _IsEmpty(self)
end

local _Delete = ShardIndex.Delete
function ShardIndex:Delete(cb, save_options)
    self.adventure:DeleteWithOriginal(_Delete, cb, save_options)
end

local _SetServerShardData = ShardIndex.SetServerShardData
function ShardIndex:SetServerShardData(customoptions, serverdata, onsavedcb)
    self.adventure:SetServerShardDataWithOriginal(_SetServerShardData, customoptions, serverdata, onsavedcb)
end

local _OnGenerateNewWorld = ShardIndex.OnGenerateNewWorld
function ShardIndex:OnGenerateNewWorld(savedata, metadataStr, session_identifier, cb)
    self.adventure:OnGenerateNewWorldWithOriginal(_OnGenerateNewWorld, savedata, metadataStr, session_identifier, cb)
end
