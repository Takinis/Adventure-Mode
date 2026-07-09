local AddPrefabPostInit = AddPrefabPostInit
GLOBAL.setfenv(1, GLOBAL)

local ADVENTURE_DEATH_CHECK_POLL_INTERVAL = 0.25
local ADVENTURE_DEATH_CHECK_INITIAL_DELAY = 0.1

local function is_master_shard()
    return ShardWorldIndex ~= nil and ShardWorldIndex:IsMasterShard()
end

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

local function player_is_dead_or_ghost(player)
    return player ~= nil and
        (player:HasTag("playerghost") or
        (player.components.health ~= nil and player.components.health:IsDead()))
end

local function all_adventure_players_dead()
    if TheWorld == nil or not TheWorld.ismastersim or not is_master_shard() then
        return false
    end

    local total = 0
    local alive = 0
    if AllPlayers ~= nil then
        for _, player in ipairs(AllPlayers) do
            if player.userid ~= nil and player.userid ~= "" then
                total = total + 1
                if not player_is_dead_or_ghost(player) then
                    alive = alive + 1
                end
            end
        end
    end

    local secondary_players, secondary_ghosts = get_secondary_shard_player_counts()
    total = total + secondary_players
    alive = alive + math.max(secondary_players - secondary_ghosts, 0)

    return total > 0 and alive <= 0
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

local function start_adventure_death_check(inst)
    if inst._adventure_death_check_task ~= nil or not is_master_shard() or not inst:IsAdventureActive() then
        return
    end

    local function check()
        inst._adventure_death_check_task = nil

        if not inst:IsAdventureActive() then
            return
        end

        if all_adventure_players_dead() then
            ShardGameIndex.adventure:ReturnFromShard("death")
            return
        end

        inst._adventure_death_check_task = inst:DoTaskInTime(ADVENTURE_DEATH_CHECK_POLL_INTERVAL, check)
    end

    inst._adventure_death_check_task = inst:DoTaskInTime(ADVENTURE_DEATH_CHECK_INITIAL_DELAY, check)
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

    function inst:StartAdventureDeathCheck()
        start_adventure_death_check(self)
    end

    inst:DoTaskInTime(0, function()
        inst:StartAdventureDeathCheck()
    end)
end)
