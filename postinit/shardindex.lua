-- Attach adventure state after ShardWorldIndex installs its lifecycle patch.

GLOBAL.setfenv(1, GLOBAL)

local populate_world_hooked = false

local function BuildAdventureSnapshot(state)
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

local function GetAdventureSnapshot(savedata)
    local topology = savedata ~= nil and savedata.map ~= nil and savedata.map.topology or nil
    local snapshot = BuildAdventureSnapshot(topology ~= nil and topology.world_index_state or nil)
    if snapshot == nil then
        local state = ShardGameIndex ~= nil and ShardGameIndex.adventure ~= nil and
            ShardGameIndex.adventure:GetState() or nil
        snapshot = BuildAdventureSnapshot(state)
    end

    return snapshot
end

local function GetRuntimeAdventureSnapshot(inst, fallback)
    if inst ~= nil and inst.ismastersim then
        local manager = ShardGameIndex ~= nil and ShardGameIndex.adventure or nil
        if manager ~= nil then
            return BuildAdventureSnapshot(manager:GetState())
        end
        return fallback
    end

    local adventure = inst ~= nil and inst.net ~= nil and inst.net.components ~= nil and
        inst.net.components.adventure or nil
    if adventure ~= nil then
        return adventure:GetSnapshot()
    end
    return fallback
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
                            return GetRuntimeAdventureSnapshot(inst, adventure_snapshot) ~= nil
                        end
                        function inst:GetAdventureChapter()
                            local snapshot = GetRuntimeAdventureSnapshot(inst, adventure_snapshot)
                            return snapshot ~= nil and snapshot.chapter or nil
                        end
                        function inst:GetAdventureChapterCount()
                            local snapshot = GetRuntimeAdventureSnapshot(inst, adventure_snapshot)
                            return snapshot ~= nil and snapshot.chapter_count or nil
                        end
                        function inst:GetAdventurePreset()
                            local snapshot = GetRuntimeAdventureSnapshot(inst, adventure_snapshot)
                            return snapshot ~= nil and snapshot.preset or nil
                        end
                        function inst:IsAdventurePreset(preset)
                            local snapshot = GetRuntimeAdventureSnapshot(inst, adventure_snapshot)
                            return snapshot ~= nil and snapshot.preset == preset
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
                        local snapshot = GetRuntimeAdventureSnapshot(TheWorld, adventure_snapshot)
                        local adventure = TheWorld.net ~= nil and TheWorld.net.components ~= nil and
                            TheWorld.net.components.adventure or nil
                        if adventure ~= nil then
                            adventure:SetSnapshot(snapshot)
                        end
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
    self.adventure = ShardAdventureIndex(self)
end

local _Load = ShardIndex.Load
local function LoadWorldIndexState(self, callback)
    self.worldindex:LoadSidecar(function(success)
        if success == false then
            callback(false)
            return
        end
        self.adventure:MigrateLoadedState(callback)
    end, "adventure")
end

function ShardIndex:Load(callback)
    _Load(self, function(...)
        local args = { ... }
        LoadWorldIndexState(self, function(success)
            if callback ~= nil then
                if success == false then
                    callback(false)
                else
                    callback(unpack(args))
                end
            end
        end)
    end)
end

local _LoadShardInSlot = ShardIndex.LoadShardInSlot
function ShardIndex:LoadShardInSlot(slot, shard, callback)
    _LoadShardInSlot(self, slot, shard, function(...)
        local args = { ... }
        LoadWorldIndexState(self, function(success)
            if callback ~= nil then
                if success == false then
                    callback(false)
                else
                    callback(unpack(args))
                end
            end
        end)
    end)
end
