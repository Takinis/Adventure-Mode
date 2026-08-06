-- Patch vanilla ShardIndex lifecycle methods so WorldIndex can
-- keep sidecar state in sync. Adventure Mode is one consumer of this layer.

GLOBAL.setfenv(1, GLOBAL)

local populate_world_hooked = false

local function GetAdventureSnapshot(savedata)
    local topology = savedata ~= nil and savedata.map ~= nil and savedata.map.topology or nil
    local state = topology ~= nil and (topology.world_index_state or topology.adventure_state) or nil

    if type(state) ~= "table" or state.kind ~= "adventure" or state.active ~= true then
        state = ShardGameIndex ~= nil and ShardGameIndex.adventure ~= nil and
            ShardGameIndex.adventure:GetState() or nil
    end

    if type(state) ~= "table" or state.kind ~= "adventure" or state.active ~= true then
        return nil
    end

    local chapter_count = state.total_chapters
    if chapter_count == nil and type(state.level_sequence) == "table" then
        chapter_count = #state.level_sequence
    end

    return
    {
        active = true,
        secondary = state.secondary == true,
        chapter = state.chapter,
        chapter_count = chapter_count,
        preset = state.current_preset,
    }
end

local function HookPopulateWorld()
    if populate_world_hooked then
        return
    end

    local level = 2
    while debug.getinfo(level, "f") ~= nil do
        local index = 1
        while true do
            local name, _PopulateWorld = debug.getlocal(level, index)
            if name == nil then
                break
            end

            if name == "PopulateWorld" and type(_PopulateWorld) == "function" then
                local function PopulateWorld(savedata, profile)
                    if savedata == nil then
                        return _PopulateWorld(savedata, profile)
                    end

                    local prefab = assert(Prefabs[savedata.map.prefab], "Failed to find world prefab")
                    local constructor = prefab.fn
                    local is_adventure = savedata.map.topology.overrides.is_adventure
                    local adventure_snapshot = GetAdventureSnapshot(savedata)
                    local common_postinit, common_scope_fn, common_postinit_index = ToolUtil.GetUpvalue(constructor, "common_postinit")
                    local master_postinit, master_scope_fn, master_postinit_index = ToolUtil.GetUpvalue(constructor, "master_postinit")
                    assert(common_postinit ~= nil, "Failed to find world constructor common_postinit")
                    assert(master_postinit ~= nil, "Failed to find world constructor master_postinit")

                    debug.setupvalue(common_scope_fn, common_postinit_index, function(inst, ...)
                        inst.is_adventure = is_adventure
                        function inst:IsAdventureActive()
                            return adventure_snapshot ~= nil
                        end
                        function inst:GetAdventureChapter()
                            return adventure_snapshot ~= nil and adventure_snapshot.chapter or nil
                        end
                        function inst:GetAdventureChapterCount()
                            return adventure_snapshot ~= nil and adventure_snapshot.chapter_count or nil
                        end
                        function inst:GetAdventurePreset()
                            return adventure_snapshot ~= nil and adventure_snapshot.preset or nil
                        end
                        function inst:IsAdventurePreset(preset)
                            return adventure_snapshot ~= nil and adventure_snapshot.preset == preset
                        end
                        return common_postinit(inst, ...)
                    end)
                    debug.setupvalue(master_scope_fn, master_postinit_index, function(inst, ...)
                        inst.is_adventure = is_adventure
                        function inst:GetSecondaryShardPlayerCount()
                            return ShardWorldIndex:GetSecondaryShardPlayerCount()
                        end
                        return master_postinit(inst, ...)
                    end)

                    local rets = { pcall(_PopulateWorld, savedata, profile) }
                    debug.setupvalue(common_scope_fn, common_postinit_index, common_postinit)
                    debug.setupvalue(master_scope_fn, master_postinit_index, master_postinit)
                    if not rets[1] then
                        error(rets[2], 0)
                    end

                    if TheWorld.ismastersim then
                        TheWorld.net.components.adventure:SetSnapshot(adventure_snapshot)
                    end
                    return unpack(rets, 2)
                end

                debug.setlocal(level, index, PopulateWorld)
                populate_world_hooked = true
                return
            end

            index = index + 1
        end
        level = level + 1
    end
end

local _ctor = ShardIndex._ctor
function ShardIndex._ctor(self, ...)
    _ctor(self, ...)
    HookPopulateWorld()
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
    if not self.preserve_world_index_sidecar then
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

    self.worldindex:PrepareDelete(save_options, function(success)
        if success then
            _Delete(self, cb, save_options)
        elseif cb ~= nil then
            cb(false)
        end
    end)
end

local _SetServerShardData = ShardIndex.SetServerShardData
function ShardIndex:SetServerShardData(customoptions, serverdata, onsavedcb)
    local function set_server_shard_data(success)
        if success ~= false then
            _SetServerShardData(self, customoptions, serverdata, onsavedcb)
        elseif onsavedcb ~= nil then
            onsavedcb(false)
        end
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
