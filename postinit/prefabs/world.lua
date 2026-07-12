local AddPrefabPostInit = AddPrefabPostInit
GLOBAL.setfenv(1, GLOBAL)

local function get_secondary_shard_player_counts()
    if ShardWorldIndex == nil then
        return 0, 0
    end

    return ShardWorldIndex:GetSecondaryShardPlayerCounts()
end

local function get_adventure_state_component(inst)
    local world_net = inst ~= nil and inst.net or nil
    return world_net ~= nil and
        world_net.components ~= nil and
        world_net.components.adventure or nil
end

local function get_secondary_shard_player_count()
    local secondary_players = get_secondary_shard_player_counts()
    return secondary_players
end

local function is_adventure_active(inst)
    local adventure = get_adventure_state_component(inst)

    if adventure ~= nil then
        return adventure:IsActive()
    end
end

local function get_adventure_level(inst)
    local adventure = get_adventure_state_component(inst)
    return adventure ~= nil and adventure:GetLevel() or nil
end

local function is_adventure_level(inst, level)
    local adventure = get_adventure_state_component(inst)
    return adventure ~= nil and adventure:IsLevel(level)
end

AddPrefabPostInit("world", function(inst)

    inst.IsAdventureActive = is_adventure_active
    inst.GetAdventureLevel = get_adventure_level
    inst.IsAdventureLevel = is_adventure_level

    if not TheWorld.ismastersim then
        return
    end

    if inst.components.blockertransversewall == nil then
        inst:AddComponent("blockertransversewall")
    end

    if inst.components.adventuremanager == nil then
        inst:AddComponent("adventuremanager")
    end

    function inst:GetSecondaryShardPlayerCount()
        return get_secondary_shard_player_count()
    end

end)
