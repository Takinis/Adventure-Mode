GLOBAL.setfenv(1, GLOBAL)

ShardWorldIndex = Class(function(self)
end)

local SECONDARY_SHARD_WAIT_TIMEOUT = 30
local SECONDARY_SHARD_WAIT_POLL_INTERVAL = 0.5
local SECONDARY_SHARD_SETTLE_DELAY = 0.25
local WORLDGENOVERRIDE_FILE = "../worldgenoverride.lua"
local DEFAULT_SECONDARY_LEVEL =
{
    worldgen_preset = "DST_CAVE",
    settings_preset = "DST_CAVE",
    overrides =
    {
        world_size = "small",
    },
}

local function noop()
end

local function deepcopy_safe(value)
    return value ~= nil and deepcopy(value) or nil
end

local function is_master_shard()
    if Shard_IsMaster ~= nil then
        return Shard_IsMaster()
    end
    if TheShard ~= nil and TheShard.IsMaster ~= nil and TheShard:IsMaster() then
        return true
    end
    return TheNet ~= nil and TheShard ~= nil and
        TheNet:GetIsMasterSimulation() and
        (TheShard.IsSecondary == nil or not TheShard:IsSecondary())
end

local function get_slot_and_shard(index)
    return index:GetSlot(), index:GetShard()
end

local function get_index_shard(index)
    local shard = index ~= nil and index.GetShard ~= nil and index:GetShard() or nil
    if shard ~= nil and shard ~= "" then
        return shard
    end
    if TheShard ~= nil and TheShard.IsSecondary ~= nil and TheShard:IsSecondary() then
        return "Caves"
    end
    return "Master"
end

local function is_master_shard_id(shardid)
    return shardid == nil or shardid == "" or shardid == SHARDID.MASTER or shardid == "Master"
end

local function read_worldgenoverride_raw(index, cb)
    cb = cb or noop

    local slot, shard = get_slot_and_shard(index)
    local function onload(load_success, str)
        if load_success and str ~= nil and #str > 0 then
            cb(str)
        else
            cb(nil)
        end
    end

    if slot ~= nil and shard ~= nil then
        TheSim:GetPersistentStringInClusterSlot(slot, shard, WORLDGENOVERRIDE_FILE, onload)
    else
        TheSim:GetPersistentString(WORLDGENOVERRIDE_FILE, onload)
    end
end

local function write_worldgenoverride_str(index, str, cb)
    cb = cb or noop

    local slot, shard = get_slot_and_shard(index)
    if slot ~= nil and shard ~= nil then
        TheSim:SetPersistentStringInClusterSlot(slot, shard, WORLDGENOVERRIDE_FILE, str, false, cb)
    else
        TheSim:SetPersistentString(WORLDGENOVERRIDE_FILE, str, false, cb)
    end
end

local function restore_worldgenoverride(index, raw, cb)
    write_worldgenoverride_str(index, raw or "return {\n\toverride_enabled = false,\n}\n", cb)
end

local function get_return_position()
    local player = ThePlayer or (AllPlayers ~= nil and AllPlayers[1]) or nil
    if player ~= nil and player.Transform ~= nil then
        local x, y, z = player.Transform:GetWorldPosition()
        return { x = x, y = y, z = z }
    end
end

local function save_players()
    if AllPlayers ~= nil then
        for _, player in ipairs(AllPlayers) do
            if player.userid ~= nil and #player.userid > 0 then
                SerializeUserSession(player)
            end
        end
    elseif ThePlayer ~= nil then
        SerializeUserSession(ThePlayer)
    end
end

local function get_player_session_metadata(player)
    return DataDumper({ character = player.prefab }, nil, BRANCH ~= "dev")
end

local function get_character_only_record(playerinfo)
    local skinner = type(playerinfo.data) == "table" and playerinfo.data.skinner or nil
    return
    {
        prefab = playerinfo.prefab,
        skinname = playerinfo.skinname,
        skin_id = playerinfo.skin_id,
        alt_skin_ids = deepcopy_safe(playerinfo.alt_skin_ids),
        data = skinner ~= nil and
        {
            skinner =
            {
                skin_name = skinner.skin_name,
                skin_mode = skinner.skin_mode,
                clothing =
                {
                    body = skinner.clothing ~= nil and skinner.clothing.body or "",
                    hand = skinner.clothing ~= nil and skinner.clothing.hand or "",
                    legs = skinner.clothing ~= nil and skinner.clothing.legs or "",
                    feet = skinner.clothing ~= nil and skinner.clothing.feet or "",
                },
            },
        } or nil,
    }
end

local function get_character_only_sessions(sessions)
    if sessions == nil then
        return nil
    end

    local stripped = {}
    for _, session in ipairs(sessions) do
        if session.data ~= nil then
            local success, playerinfo = RunInSandboxSafe(session.data)
            if success and type(playerinfo) == "table" and playerinfo.prefab ~= nil then
                table.insert(stripped,
                {
                    userid = session.userid,
                    prefab = session.prefab or playerinfo.prefab,
                    data = DataDumper(get_character_only_record(playerinfo), nil, BRANCH ~= "dev"),
                    metadata = session.metadata,
                    mode = "character_only",
                })
            end
        end
    end

    return #stripped > 0 and stripped or nil
end

local function collect_player_sessions()
    if AllPlayers == nil or not TheNet:GetIsServer() then
        return nil
    end

    local sessions = {}
    for _, player in ipairs(AllPlayers) do
        if player.userid ~= nil and #player.userid > 0 and player.prefab ~= nil then
            local playerinfo = player:GetSaveRecord()
            table.insert(sessions,
            {
                userid = player.userid,
                prefab = player.prefab,
                data = DataDumper(playerinfo, nil, BRANCH ~= "dev"),
                metadata = get_player_session_metadata(player),
                mode = "full",
            })
        end
    end

    return #sessions > 0 and sessions or nil
end

local function sessions_to_userid_map(sessions)
    local map = {}
    if sessions ~= nil then
        for _, session in ipairs(sessions) do
            if session.userid ~= nil and session.userid ~= "" then
                map[session.userid] = true
            end
        end
    end
    return map
end

local function session_list_to_map(sessions)
    local map = {}
    if sessions ~= nil then
        for _, session in ipairs(sessions) do
            if session.userid ~= nil and session.userid ~= "" then
                map[session.userid] = session
            end
        end
    end
    return map
end

local function merge_session_lists(primary, fallback)
    local merged = {}
    local seen = {}

    if primary ~= nil then
        for _, session in ipairs(primary) do
            if session.userid ~= nil and session.userid ~= "" then
                table.insert(merged, session)
                seen[session.userid] = true
            end
        end
    end

    if fallback ~= nil then
        for _, session in ipairs(fallback) do
            if session.userid ~= nil and session.userid ~= "" and not seen[session.userid] then
                table.insert(merged, session)
                seen[session.userid] = true
            end
        end
    end

    return #merged > 0 and merged or nil
end

local function get_player_save_session(player)
    if player == nil or player.userid == nil or player.userid == "" or player.prefab == nil then
        return nil
    end

    return
    {
        userid = player.userid,
        prefab = player.prefab,
        data = DataDumper(player:GetSaveRecord(), nil, BRANCH ~= "dev"),
        metadata = get_player_session_metadata(player),
        mode = "full",
    }
end

local function get_spawn_position_from_savedata_str(savedata)
    if type(savedata) ~= "string" or #savedata <= 0 then
        return { x = 0, y = 0, z = 0 }
    end

    local success, world = RunInSandboxSafe(savedata)
    if not success or world == nil or world.ents == nil then
        return { x = 0, y = 0, z = 0 }
    end

    local spawn_prefabs =
    {
        "spawnpoint_master",
        "spawnpoint_multiplayer",
        "multiplayer_portal",
        "quagmire_portal",
        "lavaarena_portal",
        "spawnpoint",
    }

    for _, prefab in ipairs(spawn_prefabs) do
        local ents = world.ents[prefab]
        if ents ~= nil and ents[1] ~= nil then
            return
            {
                x = ents[1].x or 0,
                y = ents[1].y or 0,
                z = ents[1].z or 0,
            }
        end
    end

    return { x = 0, y = 0, z = 0 }
end

local function read_world_session_raw(index, session_id, cb)
    cb = cb or noop
    if session_id == nil or session_id == "" then
        cb(nil)
        return
    end

    local server = index:GetServerData()
    if not TheNet:IsDedicated() and server ~= nil and not server.use_legacy_session_path then
        local slot = index:GetSlot()
        local shard = get_index_shard(index)
        local file = TheNet:GetWorldSessionFileInClusterSlot(slot, shard, session_id)
        if file ~= nil then
            TheSim:GetPersistentStringInClusterSlot(slot, shard, file, function(load_success, str)
                cb(load_success and str or nil)
            end)
            return
        end
    else
        local file = TheNet:GetWorldSessionFile(session_id)
        if file ~= nil then
            TheSim:GetPersistentString(file, function(load_success, str)
                cb(load_success and str or nil)
            end)
            return
        end
    end

    cb(nil)
end

local function world_session_exists(index, session_id, cb)
    cb = cb or noop
    read_world_session_raw(index, session_id, function(savedata)
        cb(savedata ~= nil)
    end)
end

local function move_player_record_to_spawn(data, spawn, index)
    if type(data) ~= "table" then
        return nil
    end

    local offset = (index or 1) - 1
    local radius = offset > 0 and math.min(2 + offset, 8) or 0
    local angle = offset * 2.399963229728653

    data.x = (spawn.x or 0) + math.cos(angle) * radius
    data.y = spawn.y
    data.z = (spawn.z or 0) + math.sin(angle) * radius

    data.puid = nil
    data.rx = nil
    data.ry = nil
    data.rz = nil

    if type(data.data) == "table" then
        data.data.migration = nil
    end

    return data
end

local function build_migrated_user_session_data(session, spawn, index)
    local success, data = RunInSandboxSafe(session.data or "")
    if not success or type(data) ~= "table" or data.prefab == nil then
        return session.data
    end

    move_player_record_to_spawn(data, spawn, index)
    return DataDumper(data, nil, BRANCH ~= "dev")
end

local function inject_player_sessions_into_world(index, sessions, session_identifier, savedata, cb)
    cb = cb or noop

    if sessions == nil or #sessions <= 0 or session_identifier == nil or session_identifier == "" or not TheNet:GetIsServer() then
        cb()
        return
    end

    local spawn = get_spawn_position_from_savedata_str(savedata)

    TheNet:BeginSession(session_identifier)
    for i, session in ipairs(sessions) do
        if session.userid ~= nil and session.data ~= nil then
            local data = build_migrated_user_session_data(session, spawn, i)
            TheNet:SerializeUserSession(session.userid, data, false, nil, session.metadata or "")
        end
    end

    cb()
end

local function inject_player_sessions_into_existing_world(index, session_id, sessions, cb)
    cb = cb or noop

    if session_id == nil or session_id == "" or sessions == nil or #sessions <= 0 or not TheNet:GetIsServer() then
        cb()
        return
    end

    read_world_session_raw(index, session_id, function(savedata)
        local spawn = get_spawn_position_from_savedata_str(savedata)
        TheNet:BeginSession(session_id)
        for i, session in ipairs(sessions) do
            local data = build_migrated_user_session_data(session, spawn, i)
            TheNet:SerializeUserSession(session.userid, data, false, nil, session.metadata or "")
        end
        cb()
    end)
end

local function force_local_players_to_master()
    if TheWorld == nil or not TheWorld.ismastersim or TheShard == nil or is_master_shard() then
        return
    end

    local players = {}
    if AllPlayers ~= nil then
        for _, player in ipairs(AllPlayers) do
            table.insert(players, player)
        end
    end

    for _, player in ipairs(players) do
        if player:IsValid() and player.userid ~= nil and player.userid ~= "" then
            TheWorld:PushEvent("ms_playerdespawnandmigrate",
            {
                player = player,
                portalid = nil,
                worldid = SHARDID.MASTER,
                x = 0,
                y = 0,
                z = 0,
            })
        end
    end
end

local function send_force_players_to_master_rpc(modname, rpcname)
    if SendModRPCToShard == nil or GetShardModRPC == nil or ShardList == nil or TheShard == nil then
        return
    end

    local rpc = GetShardModRPC(modname, rpcname or "ForcePlayersToMaster")
    if rpc == nil then
        return
    end

    local self_shard = TheShard:GetShardId()
    for shardid in pairs(ShardList) do
        if shardid ~= nil and shardid ~= self_shard and shardid ~= SHARDID.MASTER then
            SendModRPCToShard(rpc, shardid)
        end
    end
end

local function send_shard_rpc(modname, name, shardid, data)
    if SendModRPCToShard == nil or GetShardModRPC == nil then
        return
    end

    local rpc = GetShardModRPC(modname, name)
    if rpc == nil then
        return
    end

    local payload = data ~= nil and ZipAndEncodeString(data) or nil
    if payload ~= nil then
        SendModRPCToShard(rpc, shardid, payload)
    else
        SendModRPCToShard(rpc, shardid)
    end
end

local function send_rpc_to_other_secondary_shards(modname, name, data)
    if SendModRPCToShard == nil or GetShardModRPC == nil or ShardList == nil or TheShard == nil then
        return
    end

    local rpc = GetShardModRPC(modname, name)
    if rpc == nil then
        return
    end

    local payload = data ~= nil and ZipAndEncodeString(data) or nil
    local self_shard = TheShard:GetShardId()
    for shardid in pairs(ShardList) do
        if shardid ~= nil and shardid ~= self_shard and shardid ~= SHARDID.MASTER then
            if payload ~= nil then
                SendModRPCToShard(rpc, shardid, payload)
            else
                SendModRPCToShard(rpc, shardid)
            end
        end
    end
end

local function send_rpc_to_master_shard(modname, name, data)
    send_shard_rpc(modname, name, SHARDID.MASTER, data)
end

local function get_secondary_shard_player_count()
    if TheWorld == nil or TheShard == nil or TheShard.GetSecondaryShardPlayerCounts == nil or not is_master_shard() then
        return 0
    end

    local secondary_players = TheShard:GetSecondaryShardPlayerCounts(USERFLAGS.IS_GHOST)
    return secondary_players or 0
end

local function wait_for_secondary_shard_players_empty(cb, timeout, poll_interval)
    cb = cb or noop

    if TheWorld == nil or TheShard == nil or TheShard.GetSecondaryShardPlayerCounts == nil then
        cb()
        return
    end

    timeout = timeout or SECONDARY_SHARD_WAIT_TIMEOUT
    poll_interval = poll_interval or SECONDARY_SHARD_WAIT_POLL_INTERVAL

    local started_at = GetTime()
    local function poll()
        local secondary_players = TheShard:GetSecondaryShardPlayerCounts(USERFLAGS.IS_GHOST)
        secondary_players = secondary_players or 0

        if secondary_players <= 0 then
            TheWorld:DoTaskInTime(SECONDARY_SHARD_SETTLE_DELAY, cb)
            return
        end

        if GetTime() - started_at >= timeout then
            print("[World Switch] Timed out waiting for secondary shard players to return to master. Remaining secondary players: "..tostring(secondary_players))
            cb()
            return
        end

        TheWorld:DoTaskInTime(poll_interval, poll)
    end

    poll()
end

local function restart_current_slot(index, extra_params)
    local params = extra_params or {}
    params.reset_action = RESET_ACTION.LOAD_SLOT
    params.save_slot = index:GetSlot()
    StartNextInstance(params)
end

local function restart_current_slot_after_shard_rpc(index, extra_params)
    if TheWorld ~= nil then
        TheWorld:DoTaskInTime(0, function()
            restart_current_slot(index, extra_params)
        end)
    else
        restart_current_slot(index, extra_params)
    end
end

local function to_plain_options(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] ~= nil then
        return seen[value]
    end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do
        if type(v) ~= "function" and type(k) ~= "function" then
            out[to_plain_options(k, seen)] = to_plain_options(v, seen)
        end
    end
    return out
end

local function get_worldgen_preset_id(level)
    if type(level) == "string" then
        return level
    elseif type(level) == "table" then
        return level.worldgen_preset or level.preset or level.id
    end
end

local function get_settings_preset_id(level)
    if type(level) == "string" then
        return level
    elseif type(level) == "table" then
        local settings_preset = level.settings_preset
        if settings_preset == nil then
            settings_preset = level.preset or level.id
        end
        return settings_preset
    end
end

local function get_level_overrides(level)
    if type(level) == "table" then
        return level.overrides or (type(level.level_options) == "table" and level.level_options.overrides) or nil
    end
end

local function get_level_for_shard(level, shardid)
    if is_master_shard_id(shardid) then
        if type(level) == "table" and level.master ~= nil then
            return level.master
        end
        return level
    end

    if type(level) == "table" then
        local shard_levels = level.shards
        if type(shard_levels) == "table" then
            return shard_levels[shardid] or shard_levels.Caves or shard_levels.caves or shard_levels.secondary or shard_levels.default
        end
        return level.secondary or level.cave or level.caves or level.placeholder or DEFAULT_SECONDARY_LEVEL
    end

    return DEFAULT_SECONDARY_LEVEL
end

local function find_level_data_by_id(levels, id)
    if id == nil then
        return nil
    end

    if levels.GetDataForWorldGenID ~= nil then
        local data = levels.GetDataForWorldGenID(id)
        if data ~= nil then
            return data
        end
    end

    local level_lists =
    {
        levels.story_levels,
        levels.sandbox_levels,
        levels.custom_levels,
        levels.cave_levels,
        levels.shipwrecked_levels,
        levels.volcano_levels,
        levels.porkland_levels,
    }

    for _, level_list in ipairs(level_lists) do
        if level_list ~= nil then
            for _, level_data in ipairs(level_list) do
                if level_data.id == id then
                    return level_data
                end
            end
        end
    end
end

local function get_default_level_data(levels)
    if levels.GetDefaultLevelData ~= nil and GetLevelType ~= nil and
        ShardGameIndex ~= nil and ShardGameIndex.GetGameMode ~= nil then
        local data = levels.GetDefaultLevelData(GetLevelType(ShardGameIndex:GetGameMode()), nil)
        if data ~= nil then
            return data
        end
    end

    return levels.story_levels ~= nil and levels.story_levels[1] or {}
end

local function resolve_level_options(level)
    local Levels = require("map/levels")
    local preset_id = get_worldgen_preset_id(level)
    local data = type(level) == "table" and level.level_options or nil
    data = data or find_level_data_by_id(Levels, preset_id)
    if data == nil then
        data = get_default_level_data(Levels)
    end
    data = to_plain_options(data or {})

    local overrides = get_level_overrides(level)
    if overrides ~= nil then
        data.overrides = MergeMapsDeep(data.overrides or {}, to_plain_options(overrides))
    end

    return data
end

local function build_worldgenoverride_data(level)
    local data =
    {
        override_enabled = true,
    }

    local worldgen_preset = get_worldgen_preset_id(level)
    local settings_preset = get_settings_preset_id(level)
    if worldgen_preset ~= nil and worldgen_preset ~= false then
        data.worldgen_preset = worldgen_preset
    end
    if settings_preset ~= nil and settings_preset ~= false then
        data.settings_preset = settings_preset
    end

    local overrides = get_level_overrides(level)
    if overrides ~= nil then
        data.overrides = to_plain_options(overrides)
    end

    return data
end

local function write_level_worldgenoverride(index, level, cb)
    write_worldgenoverride_str(index, DataDumper(build_worldgenoverride_data(level), nil, false).."\n", cb)
end

local function switch_index_to_generated_world(index, level, keep_session)
    index.world = { options = resolve_level_options(level) }
    if not keep_session then
        index.session_id = nil
    end
    index:MarkDirty()
end

local function switch_index_to_existing_world(index, home)
    index.session_id = home.session_id
    index.world = deepcopy_safe(home.world) or { options = {} }
    index.server = deepcopy_safe(home.server) or {}
    index.enabled_mods = deepcopy_safe(home.enabled_mods) or {}
    index:MarkDirty()
end

local function delete_session_if_not_home(session_id, home_session_id)
    if session_id ~= nil and session_id ~= "" and session_id ~= home_session_id then
        TheNet:DeleteSession(session_id)
    end
end

function ShardWorldIndex:Noop()
    noop()
end

function ShardWorldIndex:DeepCopy(value)
    return deepcopy_safe(value)
end

function ShardWorldIndex:IsMasterShard()
    return is_master_shard()
end

function ShardWorldIndex:GetSlotAndShard(index)
    return get_slot_and_shard(index)
end

function ShardWorldIndex:GetIndexShard(index)
    return get_index_shard(index)
end

function ShardWorldIndex:GetLevelForShard(level, shardid)
    return get_level_for_shard(level, shardid)
end

function ShardWorldIndex:ReadWorldgenOverrideRaw(index, cb)
    read_worldgenoverride_raw(index, cb)
end

function ShardWorldIndex:RestoreWorldgenOverride(index, raw, cb)
    restore_worldgenoverride(index, raw, cb)
end

function ShardWorldIndex:WriteLevelWorldgenOverride(index, level, cb)
    write_level_worldgenoverride(index, level, cb)
end

function ShardWorldIndex:GetReturnPosition()
    return get_return_position()
end

function ShardWorldIndex:SavePlayers()
    save_players()
end

function ShardWorldIndex:CollectPlayerSessions()
    return collect_player_sessions()
end

function ShardWorldIndex:GetCharacterOnlySessions(sessions)
    return get_character_only_sessions(sessions)
end

function ShardWorldIndex:SessionsToUseridMap(sessions)
    return sessions_to_userid_map(sessions)
end

function ShardWorldIndex:SessionListToMap(sessions)
    return session_list_to_map(sessions)
end

function ShardWorldIndex:MergeSessionLists(primary, fallback)
    return merge_session_lists(primary, fallback)
end

function ShardWorldIndex:GetPlayerSaveSession(player)
    return get_player_save_session(player)
end

function ShardWorldIndex:InjectPlayerSessionsIntoWorld(index, sessions, session_identifier, savedata, cb)
    inject_player_sessions_into_world(index, sessions, session_identifier, savedata, cb)
end

function ShardWorldIndex:InjectPlayerSessionsIntoExistingWorld(index, session_id, sessions, cb)
    inject_player_sessions_into_existing_world(index, session_id, sessions, cb)
end

function ShardWorldIndex:WorldSessionExists(index, session_id, cb)
    world_session_exists(index, session_id, cb)
end

function ShardWorldIndex:ForceLocalPlayersToMaster()
    force_local_players_to_master()
end

function ShardWorldIndex:SendForcePlayersToMasterRPC(modname, rpcname)
    send_force_players_to_master_rpc(modname, rpcname)
end

function ShardWorldIndex:SendShardRPC(modname, name, shardid, data)
    send_shard_rpc(modname, name, shardid, data)
end

function ShardWorldIndex:SendRPCToOtherSecondaryShards(modname, name, data)
    send_rpc_to_other_secondary_shards(modname, name, data)
end

function ShardWorldIndex:SendRPCToMasterShard(modname, name, data)
    send_rpc_to_master_shard(modname, name, data)
end

function ShardWorldIndex:GetSecondaryShardPlayerCount()
    return get_secondary_shard_player_count()
end

function ShardWorldIndex:WaitForSecondaryShardPlayersEmpty(cb, timeout, poll_interval)
    wait_for_secondary_shard_players_empty(cb, timeout, poll_interval)
end

function ShardWorldIndex:RestartCurrentSlotAfterShardRPC(index, extra_params)
    restart_current_slot_after_shard_rpc(index, extra_params)
end

function ShardWorldIndex:SwitchIndexToGeneratedWorld(index, level, keep_session)
    switch_index_to_generated_world(index, level, keep_session)
end

function ShardWorldIndex:SwitchIndexToExistingWorld(index, home)
    switch_index_to_existing_world(index, home)
end

function ShardWorldIndex:DeleteSessionIfNotHome(session_id, home_session_id)
    delete_session_if_not_home(session_id, home_session_id)
end
