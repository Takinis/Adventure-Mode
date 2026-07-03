local AddPrefabPostInit = AddPrefabPostInit
GLOBAL.setfenv(1, GLOBAL)

local function get_world_switch_file_id()
    return Settings ~= nil and Settings.world_switch_file_id or nil
end

local function get_world_switch_state(file_id)
    if ShardGameIndex == nil or ShardGameIndex.worldindex == nil then
        return nil
    end

    return ShardGameIndex.worldindex:GetState(file_id) or ShardGameIndex.worldindex:GetState()
end

local function apply_world_switch_clock_snapshot(inst, state)
    if ShardGameIndex == nil or
        ShardGameIndex.worldindex == nil or
        TheWorld == nil or
        not TheWorld.ismastersim or
        inst.components == nil or
        inst.components.clock == nil then
        return false
    end

    local clock_snapshot = state ~= nil and
        state.active == true and
        state.kind ~= "adventure" and
        state.clock_snapshot or nil
    if type(clock_snapshot) ~= "table" or clock_snapshot.cycles == nil then
        return false
    end

    local clock = inst.components.clock
    local data = clock.OnSave ~= nil and clock:OnSave() or {}
    data.cycles = clock_snapshot.cycles
    if clock_snapshot.mooomphasecycle ~= nil then
        data.mooomphasecycle = clock_snapshot.mooomphasecycle
    end
    if clock.OnLoad ~= nil then
        clock:OnLoad(data)
        clock:LongUpdate(0)
    else
        return false
    end

    state.clock_snapshot_applied = clock_snapshot.cycles
    state.clock_snapshot = nil
    ShardGameIndex.worldindex:WriteSidecar(state)
    return true
end

local function sync_world_switch_clock(inst)
    local file_id = get_world_switch_file_id()
    if apply_world_switch_clock_snapshot(inst, get_world_switch_state(file_id)) then
        return
    end

    if ShardGameIndex == nil or ShardGameIndex.worldindex == nil then
        return
    end

    ShardGameIndex.worldindex:ReadSidecar(function(state)
        if state ~= nil then
            ShardGameIndex.worldindex:SetState(state, file_id or state.file_id)
            apply_world_switch_clock_snapshot(inst, state)
        end
    end, file_id)
end

local function add_world_switch_clock_sync(inst)
    if not TheWorld.ismastersim then
        return
    end

    local _SetPersistData = inst.SetPersistData
    function inst:SetPersistData(data, ...)
        local result = { _SetPersistData(self, data, ...) }
        sync_world_switch_clock(self)
        return unpack(result)
    end

    inst:DoTaskInTime(0, sync_world_switch_clock)
end

AddPrefabPostInit("forest_network", function(inst)
    if inst.components.adventurestate == nil then
        inst:AddComponent("adventurestate")
    end
    add_world_switch_clock_sync(inst)
end)

AddPrefabPostInit("cave_network", function(inst)
    if inst.components.adventurestate == nil then
        inst:AddComponent("adventurestate")
    end
    add_world_switch_clock_sync(inst)
end)
