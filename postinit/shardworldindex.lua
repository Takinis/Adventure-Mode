GLOBAL.setfenv(1, GLOBAL)

ShardWorldIndex = Class(function(self, index)
    self.index = index
end)

local SECONDARY_SHARD_WAIT_TIMEOUT = 30
local SECONDARY_SHARD_WAIT_POLL_INTERVAL = 0.5
local SECONDARY_SHARD_SETTLE_DELAY = 0.25
local WORLDGENOVERRIDE_FILE = "../worldgenoverride.lua"
local WORLD_TYPE_LOCATION =
{
    forest = "forest",
    caves = "cave",
    cave = "cave",
    shipwrecked = "shipwrecked",
    sw = "shipwrecked",
    volcano = "volcano",
    porkland = "porkland",
    hamlet = "porkland",
}
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

local function is_shard_index(value)
    return type(value) == "table" and
        type(value.GetSession) == "function" and
        type(value.GetSlot) == "function"
end

local function resolve_index_args(self, index, ...)
    if self ~= ShardWorldIndex and self.index ~= nil and not is_shard_index(index) then
        return self.index, index, ...
    end
    return index, ...
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

local function get_player_classified_entity(userid)
    if userid == nil or userid == "" or AllPlayers == nil then
        return nil
    end

    for _, player in ipairs(AllPlayers) do
        if player.userid == userid then
            return player.player_classified ~= nil and player.player_classified.entity or nil
        end
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

    save_players()

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

local function normalize_position(pos)
    if type(pos) ~= "table" then
        return nil
    end

    local x = tonumber(pos.x or pos[1])
    local y = tonumber(pos.y or pos[2])
    local z = tonumber(pos.z or pos[3])
    if x == nil or z == nil then
        return nil
    end

    return { x = x, y = y or 0, z = z }
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

local function get_savedata_table(savedata)
    if type(savedata) == "table" then
        return savedata
    end

    if type(savedata) ~= "string" or #savedata <= 0 then
        return nil
    end

    local success, data = RunInSandboxSafe(savedata)
    return success and type(data) == "table" and data or nil
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
            TheNet:SerializeUserSession(session.userid, data, false, get_player_classified_entity(session.userid), session.metadata or "")
        end
    end

    cb()
end

local function inject_player_sessions_into_existing_world(index, session_id, sessions, cb, spawn_override)
    cb = cb or noop

    if session_id == nil or session_id == "" or sessions == nil or #sessions <= 0 or not TheNet:GetIsServer() then
        cb()
        return
    end

    read_world_session_raw(index, session_id, function(savedata)
        local spawn = normalize_position(spawn_override) or get_spawn_position_from_savedata_str(savedata)
        TheNet:BeginSession(session_id)
        for i, session in ipairs(sessions) do
            local data = build_migrated_user_session_data(session, spawn, i)
            TheNet:SerializeUserSession(session.userid, data, false, get_player_classified_entity(session.userid), session.metadata or "")
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

local function get_secondary_shard_player_counts()
    if TheWorld == nil or TheShard == nil or TheShard.GetSecondaryShardPlayerCounts == nil or not is_master_shard() then
        return 0, 0
    end

    local secondary_players, secondary_ghosts = TheShard:GetSecondaryShardPlayerCounts(USERFLAGS.IS_GHOST)
    return secondary_players or 0, secondary_ghosts or 0
end

local function get_secondary_shard_player_count()
    local secondary_players = get_secondary_shard_player_counts()
    return secondary_players
end

local function wait_for_secondary_shard_players_empty(cb, timeout, poll_interval)
    cb = cb or noop

    if TheWorld == nil or TheShard == nil or TheShard.GetSecondaryShardPlayerCounts == nil or not is_master_shard() then
        cb()
        return
    end

    timeout = timeout or SECONDARY_SHARD_WAIT_TIMEOUT
    poll_interval = poll_interval or SECONDARY_SHARD_WAIT_POLL_INTERVAL

    local started_at = GetTime()
    local function poll()
        local secondary_players = get_secondary_shard_player_counts()

        if secondary_players <= 0 then
            TheWorld:DoTaskInTime(SECONDARY_SHARD_SETTLE_DELAY, cb)
            return
        end

        if GetTime() - started_at >= timeout then
            print("[Shard World Index] Timed out waiting for secondary shard players to return to master. Remaining secondary players: "..tostring(secondary_players))
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

local function normalize_world_type(world_type)
    if world_type == nil then
        return nil
    end
    world_type = string.lower(tostring(world_type))
    return WORLD_TYPE_LOCATION[world_type] or world_type
end

local function build_generated_level_from_target(target)
    local level =
    {
        id = target.id,
        worldgen_preset = target.worldgen_preset,
        settings_preset = target.settings_preset,
        preset = target.preset,
        current_preset = target.current_preset,
        world_type = target.world_type,
        location = target.location or target.world_type,
        dlc = target.dlc,
        mode = target.mode,
        overrides = deepcopy_safe(target.overrides),
        level_options = deepcopy_safe(target.level_options),
        master = deepcopy_safe(target.master),
        secondary = deepcopy_safe(target.secondary),
        cave = deepcopy_safe(target.cave),
        caves = deepcopy_safe(target.caves),
        placeholder = deepcopy_safe(target.placeholder),
        shards = deepcopy_safe(target.shards),
    }

    return level
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

    if levels.GetDataForLevelID ~= nil then
        local data = levels.GetDataForLevelID(id)
        if data ~= nil then
            return data
        end
    end

    if levels.GetDataForWorldGenID ~= nil then
        local data = levels.GetDataForWorldGenID(id)
        if data ~= nil then
            return data
        end
    end

    if levels.GetDataForSettingsID ~= nil then
        local data = levels.GetDataForSettingsID(id)
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

local function find_default_level_data_by_location(levels, location)
    location = normalize_world_type(location)
    if location == nil then
        return nil
    end

    if levels.GetDefaultLevelData ~= nil then
        local data = levels.GetDefaultLevelData(LEVELTYPE.SURVIVAL, location)
        if data ~= nil then
            return data
        end

        for _, leveltype in pairs(LEVELTYPE) do
            if leveltype ~= LEVELTYPE.SURVIVAL then
                data = levels.GetDefaultLevelData(leveltype, location)
                if data ~= nil then
                    return data
                end
            end
        end
    end

    local level_lists =
    {
        levels.sandbox_levels,
        levels.story_levels,
        levels.custom_levels,
        levels.cave_levels,
        levels.shipwrecked_levels,
        levels.volcano_levels,
        levels.porkland_levels,
    }

    for _, level_list in ipairs(level_lists) do
        if level_list ~= nil then
            for _, level_data in ipairs(level_list) do
                if normalize_world_type(level_data.location) == location then
                    return level_data
                end
            end
        end
    end
end

local function get_level_world_type(level)
    return type(level) == "table" and normalize_world_type(level.world_type or level.location or level.dlc or level.mode) or nil
end

local function worldgen_preset_exists(levels, preset)
    return type(preset) == "string" and preset ~= "" and
        levels.GetDataForWorldGenID ~= nil and levels.GetDataForWorldGenID(preset) ~= nil
end

local function settings_preset_exists(levels, preset)
    return preset == nil or preset == false or
        (type(preset) == "string" and preset ~= "" and
        levels.GetDataForSettingsID ~= nil and levels.GetDataForSettingsID(preset) ~= nil)
end

local function validate_world_switch_generated_level(level)
    local Levels = require("map/levels")
    local world_type = get_level_world_type(level)
    local worldgen_preset = get_worldgen_preset_id(level)
    local settings_preset = get_settings_preset_id(level)

    if worldgen_preset == nil and world_type ~= nil then
        local level_data = find_default_level_data_by_location(Levels, world_type)
        if level_data == nil then
            return false, "no default preset exists for world type "..tostring(world_type)
        end
        worldgen_preset = get_worldgen_preset_id(level_data)
        settings_preset = settings_preset or get_settings_preset_id(level_data)
    end

    if worldgen_preset == nil or worldgen_preset == false then
        return false, "target worldgen preset is missing"
    end

    if not worldgen_preset_exists(Levels, worldgen_preset) then
        return false, "target worldgen preset does not exist: "..tostring(worldgen_preset)
    end

    if not settings_preset_exists(Levels, settings_preset) then
        return false, "target settings preset does not exist: "..tostring(settings_preset)
    end

    return true
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
    local world_type = get_level_world_type(level)
    local data = type(level) == "table" and level.level_options or nil
    data = data or find_level_data_by_id(Levels, preset_id)
    data = data or find_default_level_data_by_location(Levels, world_type)
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
    local world_type = get_level_world_type(level)
    if worldgen_preset == nil and world_type ~= nil then
        local Levels = require("map/levels")
        local level_data = find_default_level_data_by_location(Levels, world_type)
        worldgen_preset = get_worldgen_preset_id(level_data)
        settings_preset = settings_preset or get_settings_preset_id(level_data)
    end
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

local function build_level_worldgenoverride_raw(level)
    return DataDumper(build_worldgenoverride_data(level), nil, false).."\n"
end

local function write_level_worldgenoverride(index, level, cb)
    write_worldgenoverride_str(index, build_level_worldgenoverride_raw(level), cb)
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

local function switch_index_to_current_world(index, state)
    if state == nil or state.current_session_id == nil or state.current_session_id == "" then
        return false
    end

    local home = state.home or state.main or {}
    index.session_id = state.current_session_id
    index.world = deepcopy_safe(state.current_world) or { options = {} }
    index.server = deepcopy_safe(state.current_server) or deepcopy_safe(home.server) or {}
    index.enabled_mods = deepcopy_safe(state.current_enabled_mods) or deepcopy_safe(home.enabled_mods) or {}
    index:MarkDirty()
    return true
end

local function delete_session_if_not_home(session_id, home_session_id)
    if session_id ~= nil and session_id ~= "" and session_id ~= home_session_id then
        TheNet:DeleteSession(session_id)
    end
end

local DEFAULT_WORLD_SWITCH_FILE_ID = "world"
local ADVENTURE_WORLD_SWITCH_FILE_ID = "adventure"
local WORLD_SWITCH_KNOWN_FILE_IDS =
{
    DEFAULT_WORLD_SWITCH_FILE_ID,
    ADVENTURE_WORLD_SWITCH_FILE_ID,
    "forest",
    "cave",
    "caves",
    "shipwrecked",
    "volcano",
    "porkland",
}

local function normalize_world_switch_file_id(file_id)
    if file_id == nil or file_id == "" then
        return DEFAULT_WORLD_SWITCH_FILE_ID
    end

    file_id = string.lower(tostring(file_id)):gsub("[^%w_%-]", "_")
    file_id = file_id:gsub("_+", "_"):gsub("^_+", ""):gsub("_+$", "")
    return file_id ~= "" and file_id or DEFAULT_WORLD_SWITCH_FILE_ID
end

local function add_world_switch_file_id(list, seen, file_id)
    file_id = normalize_world_switch_file_id(file_id)
    if not seen[file_id] then
        seen[file_id] = true
        table.insert(list, file_id)
    end
end

local function get_known_world_switch_file_ids(extra_file_id)
    local ids = {}
    local seen = {}

    if extra_file_id ~= nil then
        add_world_switch_file_id(ids, seen, extra_file_id)
    end
    if Settings ~= nil and Settings.world_switch_file_id ~= nil then
        add_world_switch_file_id(ids, seen, Settings.world_switch_file_id)
    end
    for _, file_id in ipairs(WORLD_SWITCH_KNOWN_FILE_IDS) do
        add_world_switch_file_id(ids, seen, file_id)
    end
    for _, file_id in pairs(WORLD_TYPE_LOCATION) do
        add_world_switch_file_id(ids, seen, file_id)
    end

    return ids
end

local function get_world_switch_home_state(state)
    return state ~= nil and (state.home or state.main) or nil
end

local function ensure_world_switch_home_aliases(state)
    if state ~= nil then
        state.file_id = normalize_world_switch_file_id(state.file_id)
        if state.home == nil and state.main ~= nil then
            state.home = state.main
        elseif state.main == nil and state.home ~= nil then
            state.main = state.home
        end
    end
    return state
end

local function world_switch_state_reserves_slot(state)
    ensure_world_switch_home_aliases(state)
    local home = get_world_switch_home_state(state)
    return state ~= nil and
        state.active == true and
        home ~= nil and
        home.session_id ~= nil and
        home.session_id ~= ""
end

local function world_switch_state_matches_current_session(index, state)
    local session_id = index ~= nil and index.GetSession ~= nil and index:GetSession() or nil
    return session_id ~= nil and
        session_id ~= "" and
        state ~= nil and
        state.current_session_id == session_id
end

local function get_world_switch_sidecar_filename(index, file_id)
    return index:GetShardIndexName().."_"..normalize_world_switch_file_id(file_id)
end

local function read_named_world_switch_sidecar(index, file_id, cb)
    cb = cb or noop
    file_id = normalize_world_switch_file_id(file_id)

    local filename = get_world_switch_sidecar_filename(index, file_id)
    local slot, shard = get_slot_and_shard(index)
    local function onload(load_success, str)
        if load_success and str ~= nil and #str > 0 then
            local success, data = RunInSandboxSafe(str)
            if success and type(data) == "table" then
                data.file_id = normalize_world_switch_file_id(data.file_id or file_id)
                ensure_world_switch_home_aliases(data)
                cb(data, true)
                return
            end
            print("[Shard World Index] Failed to parse "..filename)
            cb(nil, true)
            return
        end
        cb(nil, false)
    end

    if slot ~= nil and shard ~= nil then
        TheSim:GetPersistentStringInClusterSlot(slot, shard, filename, onload)
    else
        TheSim:GetPersistentString(filename, onload)
    end
end

local function read_world_switch_sidecar(index, cb, file_id)
    cb = cb or noop

    if file_id ~= nil then
        read_named_world_switch_sidecar(index, file_id, function(state)
            cb(state)
        end)
        return
    end

    local ids = get_known_world_switch_file_ids(index.world_switch_state ~= nil and index.world_switch_state.file_id or nil)
    local active_state = nil
    local active_state_matches_session = false
    local i = 1

    local function read_next()
        if i > #ids then
            cb(active_state)
            return
        end

        local current_file_id = ids[i]
        i = i + 1
        read_named_world_switch_sidecar(index, current_file_id, function(state)
            if state ~= nil and state.active == true then
                local matches_session = world_switch_state_matches_current_session(index, state)
                if active_state == nil or
                    (matches_session and not active_state_matches_session) or
                    (not active_state_matches_session and active_state.kind ~= "adventure" and state.kind == "adventure") then
                    active_state = state
                    active_state_matches_session = matches_session
                end
            end
            read_next()
        end)
    end

    read_next()
end

local function write_world_switch_sidecar(index, data, cb, file_id)
    cb = cb or noop
    file_id = normalize_world_switch_file_id(file_id or (data ~= nil and data.file_id or nil))

    ensure_world_switch_home_aliases(data)
    if data ~= nil then
        data.file_id = file_id
    end

    local filename = get_world_switch_sidecar_filename(index, file_id)
    local slot, shard = get_slot_and_shard(index)
    if data == nil then
        if slot ~= nil and shard ~= nil then
            -- Cluster-slot saves do not expose a Lua erase API; empty data is treated as cleared.
            TheSim:SetPersistentStringInClusterSlot(slot, shard, filename, "", false, cb)
        elseif ErasePersistentString ~= nil then
            ErasePersistentString(filename, cb)
        else
            TheSim:SetPersistentString(filename, "", false, cb)
        end
        return
    end

    local str = DataDumper(data, nil, false)
    if slot ~= nil and shard ~= nil then
        TheSim:SetPersistentStringInClusterSlot(slot, shard, filename, str, false, cb)
    else
        TheSim:SetPersistentString(filename, str, false, cb)
    end
end

local function get_world_switch_state_map(index)
    index.world_switch_states = index.world_switch_states or {}
    return index.world_switch_states
end

local function set_world_switch_state(index, state, file_id)
    if index == nil then
        return
    end

    file_id = normalize_world_switch_file_id(file_id or (state ~= nil and state.file_id or nil))
    local states = get_world_switch_state_map(index)
    if state ~= nil then
        state.file_id = file_id
        states[file_id] = ensure_world_switch_home_aliases(state)
        if index.world_switch_state == nil or state.active == true or
            normalize_world_switch_file_id(index.world_switch_state.file_id) == file_id then
            index.world_switch_state = states[file_id]
        end
    else
        states[file_id] = nil
        if index.world_switch_state ~= nil and
            normalize_world_switch_file_id(index.world_switch_state.file_id) == file_id then
            index.world_switch_state = nil
            for _, stored_state in pairs(states) do
                if stored_state.active == true then
                    index.world_switch_state = stored_state
                    break
                end
            end
        end
    end
end

local function get_world_switch_state(index, file_id)
    if index == nil then
        return nil
    end

    if file_id ~= nil then
        file_id = normalize_world_switch_file_id(file_id)
        local states = index.world_switch_states
        if states ~= nil and states[file_id] ~= nil then
            return ensure_world_switch_home_aliases(states[file_id])
        end
        if index.world_switch_state ~= nil and normalize_world_switch_file_id(index.world_switch_state.file_id) == file_id then
            return ensure_world_switch_home_aliases(index.world_switch_state)
        end
        return nil
    end

    local current_state = ensure_world_switch_home_aliases(index.world_switch_state)
    if current_state ~= nil and
        current_state.active == true and
        world_switch_state_matches_current_session(index, current_state) then
        return current_state
    end

    local states = index.world_switch_states
    if states ~= nil then
        for _, state in pairs(states) do
            if state.active == true and world_switch_state_matches_current_session(index, state) then
                index.world_switch_state = state
                return ensure_world_switch_home_aliases(state)
            end
        end
    end

    if current_state ~= nil and current_state.active == true then
        return current_state
    end

    if states ~= nil then
        for _, state in pairs(states) do
            if state.active == true then
                index.world_switch_state = state
                return ensure_world_switch_home_aliases(state)
            end
        end
    end

    return current_state
end

local function clear_world_switch_sidecar(index, cb, file_id)
    file_id = normalize_world_switch_file_id(file_id or (get_world_switch_state(index) ~= nil and get_world_switch_state(index).file_id or nil))
    set_world_switch_state(index, nil, file_id)
    write_world_switch_sidecar(index, nil, cb, file_id)
end

local function clear_all_world_switch_sidecars(index, cb)
    cb = cb or noop
    local ids = get_known_world_switch_file_ids(index.world_switch_state ~= nil and index.world_switch_state.file_id or nil)
    local i = 1

    local function clear_next()
        if i > #ids then
            index.world_switch_states = {}
            index.world_switch_state = nil
            cb()
            return
        end

        local file_id = ids[i]
        i = i + 1
        write_world_switch_sidecar(index, nil, clear_next, file_id)
    end

    clear_next()
end

local function is_world_switch_transition_restart()
    return Settings ~= nil and
        Settings.reset_action == RESET_ACTION.LOAD_SLOT and
        (Settings.world_switch_transition ~= nil or Settings.adventure_transition ~= nil)
end

local function is_load_slot()
    return Settings ~= nil and Settings.reset_action == RESET_ACTION.LOAD_SLOT
end

local function is_pending_world_generation_state(state)
    local home = get_world_switch_home_state(state)
    return state ~= nil and
        state.active == true and
        home ~= nil and
        home.session_id ~= nil and
        home.session_id ~= "" and
        (type(state.pending_generation) == "table" or
        ((state.current_session_id == nil or state.current_session_id == "") and (state.current_preset ~= nil or state.current_target ~= nil)))
end

local function should_preserve_pending_world_generation(state)
    return is_world_switch_transition_restart() or
        (is_load_slot() and is_pending_world_generation_state(state))
end

local function prepare_interrupted_world_switch_regen(index)
    index.world = { options = {} }
    index.server = {}
    index.enabled_mods = {}
    index.session_id = nil
    index:MarkDirty()
end

local function clear_interrupted_world_switch_transition(index, cb)
    cb = cb or noop
    clear_world_switch_sidecar(index, function()
        restore_worldgenoverride(index, nil, cb)
    end)
end

local function world_switch_state_has_origin(state)
    return state ~= nil and (state.slot ~= nil or state.shard ~= nil)
end

local function world_switch_state_matches_index(index, state)
    if state == nil then
        return false
    end
    if state.slot ~= nil and state.slot ~= index:GetSlot() then
        return false
    end
    return state.shard == nil or state.shard == get_index_shard(index)
end

local function build_world_switch_home_state(index, worldgenoverride, opts)
    opts = opts or {}
    return
    {
        session_id = opts.session_id or index:GetSession(),
        worldgenoverride = worldgenoverride,
        world = deepcopy_safe(index.world),
        server = deepcopy_safe(index.server),
        enabled_mods = deepcopy_safe(index.enabled_mods),
        return_position = opts.return_position or get_return_position(),
        player_sessions = opts.player_sessions,
    }
end

local function build_generation_recovery_state(index, state, source_session_id)
    source_session_id = source_session_id or (index ~= nil and index:GetSession() or nil)
    if state == nil or
        source_session_id == nil or
        source_session_id == "" or
        state.current_session_id ~= source_session_id then
        return nil
    end

    local recovery = deepcopy_safe(state)
    recovery.pending_generation = nil
    recovery.checked_existing_world = nil
    recovery.generation_source_session_id = nil
    recovery.generation_recovery_state = nil
    recovery.updated_at = os.time()
    return recovery
end

local function is_generation_source_session(state, session_id)
    if state == nil or session_id == nil or session_id == "" then
        return false
    end

    if state.generation_source_session_id == session_id then
        return true
    end

    local pending = type(state.pending_generation) == "table" and state.pending_generation or nil
    return pending ~= nil and pending.generation_source_session_id == session_id
end

local function finish_interrupted_return_to_stored_world(index, state, cb)
    cb = cb or noop

    local home = get_world_switch_home_state(state)
    if home == nil or home.session_id == nil or home.session_id == "" then
        clear_world_switch_sidecar(index, cb)
        return
    end

    state.active = false
    state.finished_at = state.finished_at or os.time()
    state.return_reason = state.return_reason or "interrupted_return"

    switch_index_to_existing_world(index, home)

    restore_worldgenoverride(index, home.worldgenoverride, function()
        index:Save(function()
            write_world_switch_sidecar(index, state, function()
                set_world_switch_state(index, state)
                cb()
            end)
        end)
    end)
end

local function suspend_current_world_switch_for_adventure(index, state, cb)
    cb = cb or noop
    state = ensure_world_switch_home_aliases(state)

    if state == nil or state.active ~= true then
        cb(nil)
        return
    end

    local session_id = index:GetSession()
    if session_id ~= nil and session_id ~= "" then
        state.current_session_id = session_id
    end
    state.current_world = deepcopy_safe(index.world) or state.current_world
    state.current_server = deepcopy_safe(index.server) or state.current_server
    state.current_enabled_mods = deepcopy_safe(index.enabled_mods) or state.current_enabled_mods

    local parent_state = deepcopy_safe(state)
    state.active = false
    state.suspend_reason = "adventure_begin"
    state.suspended_at = os.time()
    state.updated_at = os.time()

    set_world_switch_state(index, state)
    write_world_switch_sidecar(index, state, function()
        cb(parent_state)
    end, state.file_id)
end

local function attach_parent_world_switch_for_adventure(opts, parent_state)
    if opts == nil or parent_state == nil then
        return opts
    end

    opts.state = deepcopy_safe(opts.state) or {}
    opts.state.parent_world_switch_state = deepcopy_safe(parent_state)

    return opts
end

local function restore_parent_world_switch(index, state, cb)
    cb = cb or noop

    local parent_state = type(state) == "table" and state.parent_world_switch_state or nil
    if type(parent_state) ~= "table" then
        cb(true)
        return
    end

    parent_state = ensure_world_switch_home_aliases(deepcopy_safe(parent_state))
    parent_state.active = true
    parent_state.updated_at = os.time()
    parent_state.suspend_reason = nil
    parent_state.suspended_at = nil

    local session_id = index:GetSession()
    if session_id ~= nil and session_id ~= "" then
        parent_state.current_session_id = session_id
    end
    parent_state.current_world = deepcopy_safe(index.world) or parent_state.current_world
    parent_state.current_server = deepcopy_safe(index.server) or parent_state.current_server
    parent_state.current_enabled_mods = deepcopy_safe(index.enabled_mods) or parent_state.current_enabled_mods

    set_world_switch_state(index, parent_state, parent_state.file_id)
    write_world_switch_sidecar(index, parent_state, function()
        cb(true)
    end, parent_state.file_id)
end

local function recover_interrupted_generation_source(index, state, cb)
    cb = cb or noop

    local recovery = type(state.generation_recovery_state) == "table" and deepcopy_safe(state.generation_recovery_state) or nil
    if recovery == nil or not switch_index_to_current_world(index, recovery) then
        print("[Shard World Index] Returning to stored world after interrupted world generation.")
        finish_interrupted_return_to_stored_world(index, state, cb)
        return
    end

    print("[Shard World Index] Restoring previous world after interrupted world generation.")
    recovery.active = true
    recovery.pending_generation = nil
    recovery.checked_existing_world = nil
    recovery.generation_source_session_id = nil
    recovery.generation_recovery_state = nil
    recovery.updated_at = os.time()

    local worldgenoverride = recovery.current_worldgenoverride or
        (get_world_switch_home_state(recovery) ~= nil and get_world_switch_home_state(recovery).worldgenoverride or nil)

    restore_worldgenoverride(index, worldgenoverride, function()
        index:Save(function()
            write_world_switch_sidecar(index, recovery, function()
                set_world_switch_state(index, recovery)
                cb()
            end)
        end)
    end)
end

local function normalize_world_switch_target(target)
    if target == nil then
        return nil
    end

    if type(target) ~= "table" then
        return { type = "generated", level = target }
    end

    local target_type = target.type or target.kind
    if target_type == "existing" or (target.session_id ~= nil and target_type ~= "generated") then
        local out = deepcopy_safe(target) or {}
        out.type = "existing"
        return out
    end

    local out = deepcopy_safe(target) or {}
    out.type = "generated"
    out.world_type = normalize_world_type(out.world_type or out.location or out.dlc or out.mode)

    if out.level == nil then
        if out.current_preset ~= nil then
            out.level = out.current_preset
        elseif out.preset ~= nil then
            out.level = out.preset
        elseif out.id ~= nil or out.worldgen_preset ~= nil or out.settings_preset ~= nil or out.overrides ~= nil or out.level_options ~= nil or out.world_type ~= nil then
            out.level = build_generated_level_from_target(out)
        else
            out.level = target
        end
    end

    return out
end

local function normalize_world_switch_existing_target(index, target)
    target = normalize_world_switch_target(target)
    if target == nil or target.type ~= "existing" or target.session_id == nil or target.session_id == "" then
        return nil
    end

    return
    {
        type = "existing",
        session_id = target.session_id,
        worldgenoverride = target.worldgenoverride,
        world = deepcopy_safe(target.world) or deepcopy_safe(index.world) or { options = {} },
        server = deepcopy_safe(target.server) or deepcopy_safe(index.server) or {},
        enabled_mods = deepcopy_safe(target.enabled_mods) or deepcopy_safe(index.enabled_mods) or {},
        return_position = target.return_position,
        player_sessions = deepcopy_safe(target.player_sessions),
        cleanup_on_return = target.cleanup_on_return == true,
        world_type = normalize_world_type(target.world_type or target.location or target.dlc or target.mode),
        id = target.id,
    }
end

local function get_world_switch_generated_level(target, shardid)
    target = normalize_world_switch_target(target)
    if target == nil or target.type == "existing" then
        return nil
    end
    return get_level_for_shard(target.level or target.current_preset or target, shardid)
end

local function get_world_switch_preset_id(preset)
    if type(preset) == "table" then
        return preset.id or preset.worldgen_preset or preset.preset or preset.settings_preset or preset.world_type
    end
    return preset
end

local function get_world_switch_target_id(target)
    target = normalize_world_switch_target(target)
    if target == nil then
        return nil
    end
    if target.type == "existing" then
        return target.id or target.session_id
    end
    return get_world_switch_preset_id(target.level) or
        get_world_switch_preset_id(target.current_preset) or
        target.world_type
end

local function should_regenerate_current_world_switch_session(index, state)
    ensure_world_switch_home_aliases(state)

    local home = get_world_switch_home_state(state)
    local session_id = index ~= nil and index:GetSession() or nil
    return state ~= nil and
        state.active == true and
        home ~= nil and
        home.session_id ~= nil and
        home.session_id ~= "" and
        session_id ~= nil and
        session_id ~= "" and
        session_id ~= home.session_id and
        not is_pending_world_generation_state(state)
end

local function get_current_world_switch_regen_target(state)
    local generated_target = normalize_world_switch_target(state.generated_target)
    if generated_target ~= nil and generated_target.type == "generated" then
        return generated_target
    end
    return normalize_world_switch_target(state.current_target or state.current_preset)
end

local function get_current_world_switch_regen_worldgenoverride(index, state)
    if state.current_worldgenoverride ~= nil then
        return state.current_worldgenoverride
    end

    local target = get_current_world_switch_regen_target(state)
    local level = get_world_switch_generated_level(target, get_index_shard(index))
    return level ~= nil and build_level_worldgenoverride_raw(level) or nil
end

local function prepare_current_world_switch_regen(index, state, cb)
    cb = cb or noop
    if not should_regenerate_current_world_switch_session(index, state) then
        return false
    end

    local player_sessions = state.secondary ~= true and collect_player_sessions() or nil
    if player_sessions ~= nil then
        state.player_sessions = player_sessions
        if state.kind == "adventure" then
            state.adventure_player_sessions = merge_session_lists(player_sessions, state.adventure_player_sessions)
        end
    end

    local target = get_current_world_switch_regen_target(state)
    if target ~= nil and target.type == "generated" then
        state.current_target = target
        state.current_preset = get_world_switch_target_id(target) or state.current_preset
    end

    state.current_session_id = nil
    state.cleanup_session_id = nil
    state.pending_generation = nil
    state.checked_existing_world = nil
    state.generation_source_session_id = nil
    state.generation_recovery_state = nil
    state.last_player_session_injected = nil
    state.updated_at = os.time()
    set_world_switch_state(index, state)

    local worldgenoverride = get_current_world_switch_regen_worldgenoverride(index, state)
    if worldgenoverride ~= nil then
        state.current_worldgenoverride = worldgenoverride
        restore_worldgenoverride(index, worldgenoverride, function()
            write_world_switch_sidecar(index, state, cb)
        end)
    else
        write_world_switch_sidecar(index, state, cb)
    end
    return true
end

local function get_world_switch_target_file_id(target, fallback)
    target = normalize_world_switch_target(target)
    if target ~= nil then
        if target.file_id ~= nil then
            return normalize_world_switch_file_id(target.file_id)
        end
        if target.world_type ~= nil then
            return normalize_world_switch_file_id(target.world_type)
        end
        if target.type == "existing" then
            return normalize_world_switch_file_id(target.id or fallback)
        end
        local level = target.level or target.current_preset
        if type(level) == "table" then
            local world_type = normalize_world_type(level.world_type or level.location or level.dlc or level.mode)
            if world_type ~= nil then
                return normalize_world_switch_file_id(world_type)
            end
        end
        return normalize_world_switch_file_id(get_world_switch_target_id(target) or fallback)
    end

    return normalize_world_switch_file_id(fallback)
end

local function get_world_switch_target_from_opts(opts, state)
    opts = opts or {}
    return normalize_world_switch_target(opts.target or opts.world or opts.level or opts.current_preset or state and state.current_target)
end

local function apply_pending_world_generation_state(state)
    local pending = type(state.pending_generation) == "table" and state.pending_generation or nil
    if pending == nil then
        return
    end

    state.reason = pending.reason or state.reason
    state.chapter = pending.chapter or state.chapter
    state.current_target = normalize_world_switch_target(pending.target or pending.current_target or pending.current_preset or pending.level) or state.current_target
    state.current_preset = get_world_switch_preset_id(pending.current_preset) or
        get_world_switch_preset_id(pending.level) or
        get_world_switch_target_id(state.current_target) or
        state.current_preset
    state.current_session_id = nil
    state.player_sessions = deepcopy_safe(pending.player_sessions)
    state.adventure_player_sessions = deepcopy_safe(pending.adventure_player_sessions)
    state.first_chapter_start_inv_pending = pending.first_chapter_start_inv_pending == true
    state.cleanup_session_id = pending.cleanup_session_id
    state.reuse_existing = pending.reuse_existing ~= false
    state.generation_source_session_id = pending.generation_source_session_id or state.generation_source_session_id
    state.generation_recovery_state = deepcopy_safe(pending.generation_recovery_state) or state.generation_recovery_state
    if pending.file_id ~= nil then
        state.file_id = normalize_world_switch_file_id(pending.file_id)
    end

    if type(pending.state) == "table" then
        for key, value in pairs(pending.state) do
            state[key] = deepcopy_safe(value)
        end
    end

    if type(pending.clear_fields) == "table" then
        for _, key in ipairs(pending.clear_fields) do
            state[key] = nil
        end
    end

    state.pending_generation = nil
    state.updated_at = os.time()
end

local function has_pending_player_sessions(state)
    return type(state.player_sessions) == "table" and #state.player_sessions > 0
end

local function should_cleanup_world_switch_session(state)
    return state ~= nil and state.cleanup_current_on_return == true
end

local function needs_world_generation_postprocess(state, session_identifier)
    return state ~= nil and
        state.active == true and
        state.current_session_id == session_identifier and
        ((has_pending_player_sessions(state) and state.last_player_session_injected ~= session_identifier) or
        (state.cleanup_session_id ~= nil and state.cleanup_session_id ~= ""))
end

local function is_world_generation_saved_without_sidecar(state, session_identifier)
    local home = get_world_switch_home_state(state)
    return is_pending_world_generation_state(state) and
        session_identifier ~= nil and
        session_identifier ~= "" and
        home ~= nil and
        session_identifier ~= home.session_id and
        session_identifier ~= state.current_session_id
end

local function finish_generated_world_switch(index, state, session_identifier, savedata, use_existing_world, cb)
    cb = cb or noop

    if state == nil or not state.active then
        cb()
        return
    end

    local home = get_world_switch_home_state(state)
    if home == nil or home.session_id == nil or home.session_id == "" then
        print("[Shard World Index] Clearing sidecar without a stashed home world.")
        clear_world_switch_sidecar(index, cb)
        return
    end

    if session_identifier == nil or session_identifier == "" then
        cb()
        return
    end

    state.current_session_id = session_identifier
    state.updated_at = os.time()
    state.current_world = deepcopy_safe(index.world)
    state.current_server = deepcopy_safe(index.server)
    state.current_enabled_mods = deepcopy_safe(index.enabled_mods)
    state.generation_source_session_id = nil
    state.generation_recovery_state = nil
    set_world_switch_state(index, state)

    local can_process_sessions = TheNet ~= nil and TheNet:GetIsServer()
    local should_inject_players = can_process_sessions and
        has_pending_player_sessions(state) and
        state.last_player_session_injected ~= session_identifier
    local cleanup_session_id = state.cleanup_session_id

    local function save_state()
        local has_cleanup_session = cleanup_session_id ~= nil and cleanup_session_id ~= ""
        local should_cleanup_session = can_process_sessions and
            should_cleanup_world_switch_session(state) and
            has_cleanup_session and
            cleanup_session_id ~= home.session_id

        if not has_cleanup_session or cleanup_session_id == home.session_id then
            state.cleanup_session_id = nil
            write_world_switch_sidecar(index, state, cb)
            return
        end

        if not should_cleanup_session then
            state.cleanup_session_id = nil
            write_world_switch_sidecar(index, state, cb)
            return
        end

        write_world_switch_sidecar(index, state, function()
            delete_session_if_not_home(cleanup_session_id, home.session_id)
            state.cleanup_session_id = nil
            write_world_switch_sidecar(index, state, cb)
        end)
    end

    if should_inject_players then
        local function on_players_injected()
            state.player_sessions = nil
            state.last_player_session_injected = session_identifier
            save_state()
        end

        if use_existing_world then
            inject_player_sessions_into_existing_world(index, session_identifier, state.player_sessions, on_players_injected)
        else
            inject_player_sessions_into_world(index, state.player_sessions, session_identifier, savedata, on_players_injected)
        end
        return
    end

    save_state()
end

local function build_world_switch_client_state(state)
    if state == nil then
        return nil
    end

    local total_chapters = type(state.level_sequence) == "table" and #state.level_sequence or nil

    return
    {
        active = state.active == true,
        kind = state.kind,
        secondary = state.secondary == true or nil,
        reason = state.reason,
        sequence_id = state.sequence_id,
        chapter = state.chapter,
        current_preset = get_world_switch_preset_id(state.current_preset),
        current_session_id = state.current_session_id,
        current_target = get_world_switch_target_id(state.current_target),
        total_chapters = total_chapters,
        started_at = state.started_at,
        updated_at = state.updated_at,
        finished_at = state.finished_at,
        return_reason = state.return_reason,
    }
end

local function write_world_switch_topology_state(savedata, state)
    if savedata == nil or savedata.map == nil or savedata.map.topology == nil then
        return
    end

    local client_state = build_world_switch_client_state(state)
    savedata.map.topology.world_switch_state = client_state
    if state ~= nil and state.topology_key ~= nil then
        savedata.map.topology[state.topology_key] = client_state
    end
    if state ~= nil and state.kind == "adventure" then
        savedata.map.topology.adventure_state = client_state
    end
end

local function commit_world_switch_existing_target(index, state, target, cb)
    cb = cb or noop
    target = normalize_world_switch_existing_target(index, target)
    if target == nil then
        print("[Shard World Index] Missing existing target session.")
        cb(false)
        return
    end

    local cleanup_session_id = state.cleanup_session_id
    local target_file_id = state.file_id
    state.current_target = normalize_world_switch_target(target)
    state.current_preset = state.current_preset or target.id or target.session_id
    state.current_session_id = target.session_id
    if cleanup_session_id == target.session_id then
        state.cleanup_session_id = nil
    end
    state.cleanup_current_on_return = target.cleanup_on_return == true
    if not should_cleanup_world_switch_session(state) then
        state.cleanup_session_id = nil
    end
    state.updated_at = os.time()
    state.generated = state.generated == true or target.generated == true
    state.generated_target = state.generated_target or deepcopy_safe(target)
    state.world_type = target.world_type or state.world_type
    state.current_worldgenoverride = target.worldgenoverride or state.current_worldgenoverride
    state.current_world = deepcopy_safe(target.world) or state.current_world
    state.current_server = deepcopy_safe(target.server) or state.current_server
    state.current_enabled_mods = deepcopy_safe(target.enabled_mods) or state.current_enabled_mods
    state.file_id = target_file_id
    set_world_switch_state(index, state)

    switch_index_to_existing_world(index, target)

    local function save_target()
        write_world_switch_sidecar(index, state, function()
            index:Save(function()
                local sessions = state.player_sessions
                if sessions ~= nil and #sessions > 0 and TheNet ~= nil and TheNet:GetIsServer() then
                    inject_player_sessions_into_existing_world(index, target.session_id, sessions, function()
                        state.player_sessions = nil
                        state.last_player_session_injected = target.session_id
                        if should_cleanup_world_switch_session(state) and
                            cleanup_session_id ~= nil and cleanup_session_id ~= "" and cleanup_session_id ~= target.session_id then
                            delete_session_if_not_home(cleanup_session_id, target.session_id)
                            state.cleanup_session_id = nil
                        end
                        write_world_switch_sidecar(index, state, function()
                            cb(true)
                        end)
                    end)
                else
                    if should_cleanup_world_switch_session(state) and
                        cleanup_session_id ~= nil and cleanup_session_id ~= "" and cleanup_session_id ~= target.session_id then
                        delete_session_if_not_home(cleanup_session_id, target.session_id)
                        state.cleanup_session_id = nil
                        write_world_switch_sidecar(index, state, function()
                            cb(true)
                        end)
                        return
                    end
                    cb(true)
                end
            end)
        end)
    end

    if target.worldgenoverride ~= nil then
        restore_worldgenoverride(index, target.worldgenoverride, save_target)
    else
        save_target()
    end
end

local function commit_world_switch_generated_target(index, state, target, keep_session, cb)
    cb = cb or noop
    target = normalize_world_switch_target(target)

    local level = get_world_switch_generated_level(target, get_index_shard(index))
    if level == nil then
        print("[Shard World Index] Missing generated target level.")
        cb(false)
        return
    end

    local valid, reason = validate_world_switch_generated_level(level)
    if not valid then
        print("[Shard World Index] Refusing to switch world: "..tostring(reason)..".")
        cb(false)
        return
    end

    local file_id = state.file_id
    if not state.checked_existing_world and target.reuse_existing ~= false and state.reuse_existing ~= false then
        state.checked_existing_world = true
        read_world_switch_sidecar(index, function(existing_state)
            local session_id = existing_state ~= nil and existing_state.current_session_id or nil
            if session_id == nil or session_id == "" then
                commit_world_switch_generated_target(index, state, target, keep_session, cb)
                return
            end

        world_session_exists(index, session_id, function(exists)
            if exists then
                local existing_target =
                {
                        type = "existing",
                        id = existing_state.current_preset or get_world_switch_target_id(target),
                        session_id = session_id,
                        worldgenoverride = existing_state.current_worldgenoverride or build_level_worldgenoverride_raw(level),
                        world = existing_state.current_world or { options = resolve_level_options(level) },
                        server = existing_state.current_server,
                        enabled_mods = existing_state.current_enabled_mods,
                        world_type = existing_state.world_type or target.world_type,
                        generated = true,
                        cleanup_on_return = false,
                    }

                    state.generated = true
                    state.generated_target = normalize_world_switch_target(target)
                    state.cleanup_current_on_return = false
                    commit_world_switch_existing_target(index, state, existing_target, cb)
                else
                    existing_state.current_session_id = nil
                    existing_state.active = false
                    write_world_switch_sidecar(index, existing_state, function()
                        commit_world_switch_generated_target(index, state, target, keep_session, cb)
                    end, file_id)
                end
            end)
        end, file_id)
        return
    end
    state.checked_existing_world = nil

    state.current_target = target
    state.current_preset = get_world_switch_target_id(target) or get_world_switch_preset_id(level)
    state.cleanup_current_on_return = target.cleanup_on_return == true
    state.updated_at = os.time()
    state.generation_source_session_id = state.generation_source_session_id or index:GetSession()
    state.generation_recovery_state = state.generation_recovery_state or
        build_generation_recovery_state(index, state, state.generation_source_session_id)
    state.current_session_id = nil
    set_world_switch_state(index, state)
    switch_index_to_generated_world(index, level, keep_session ~= false)

    local worldgenoverride = build_level_worldgenoverride_raw(level)
    write_worldgenoverride_str(index, worldgenoverride, function()
        state.generated = true
        state.generated_target = normalize_world_switch_target(target)
        state.world_type = target.world_type
        state.current_worldgenoverride = worldgenoverride
        state.current_world = deepcopy_safe(index.world)
        state.current_server = deepcopy_safe(index.server)
        state.current_enabled_mods = deepcopy_safe(index.enabled_mods)
        write_world_switch_sidecar(index, state, function()
            index:Save(function()
                cb(true)
            end)
        end)
    end)
end

local function commit_world_switch_target(index, state, target, keep_session, cb)
    target = normalize_world_switch_target(target)
    if target == nil then
        print("[Shard World Index] Missing target world.")
        cb(false)
        return
    end
    state.file_id = normalize_world_switch_file_id(state.file_id or get_world_switch_target_file_id(target))

    if target.type == "existing" then
        commit_world_switch_existing_target(index, state, target, cb)
    else
        commit_world_switch_generated_target(index, state, target, keep_session, cb)
    end
end

local function load_world_switch_sidecar_state(index, state, cb)
    cb = cb or noop
    ensure_world_switch_home_aliases(state)

    if state == nil or not state.active then
        set_world_switch_state(index, state)
        cb()
        return
    end

    if world_switch_state_has_origin(state) and not world_switch_state_matches_index(index, state) then
        print("[Shard World Index] Clearing sidecar from another slot or shard.")
        clear_world_switch_sidecar(index, cb)
        return
    end

    local session_id = index:GetSession()
    if is_world_switch_transition_restart() then
        set_world_switch_state(index, state)
        cb()
        return
    end

    if is_generation_source_session(state, session_id) then
        world_session_exists(index, session_id, function(exists)
            if exists then
                recover_interrupted_generation_source(index, state, cb)
            else
                print("[Shard World Index] Previous world session is missing; returning to stashed home world.")
                finish_interrupted_return_to_stored_world(index, state, cb)
            end
        end)
        return
    end

    if session_id ~= nil and session_id ~= "" and is_world_generation_saved_without_sidecar(state, session_id) then
        world_session_exists(index, session_id, function(exists)
            if exists then
                print("[Shard World Index] Finishing interrupted world generation.")
                apply_pending_world_generation_state(state)
                finish_generated_world_switch(index, state, session_id, nil, true, cb)
            else
                print("[Shard World Index] Generated session is missing; returning to stashed home world.")
                finish_interrupted_return_to_stored_world(index, state, cb)
            end
        end)
        return
    end

    if session_id == nil or session_id == "" then
        if is_pending_world_generation_state(state) then
            print("[Shard World Index] Resuming interrupted world generation.")
            apply_pending_world_generation_state(state)
            set_world_switch_state(index, state)
            cb()
            return
        end

        if world_switch_state_matches_index(index, state) then
            print("[Shard World Index] Restoring stored world after interrupted transition.")
            finish_interrupted_return_to_stored_world(index, state, cb)
        else
            print("[Shard World Index] Clearing interrupted transition before regenerating the slot.")
            prepare_interrupted_world_switch_regen(index)
            clear_interrupted_world_switch_transition(index, cb)
        end
        return
    end

    if type(state.pending_generation) == "table" then
        world_session_exists(index, session_id, function(exists)
            if exists then
                set_world_switch_state(index, state)
                cb()
            else
                print("[Shard World Index] Current generated session is missing; returning to stashed home world.")
                finish_interrupted_return_to_stored_world(index, state, cb)
            end
        end)
        return
    end

    if state.current_session_id == session_id then
        world_session_exists(index, session_id, function(exists)
            if exists then
                if needs_world_generation_postprocess(state, session_id) then
                    print("[Shard World Index] Finishing pending world generation postprocess.")
                    finish_generated_world_switch(index, state, session_id, nil, true, cb)
                else
                    set_world_switch_state(index, state)
                    cb()
                end
            else
                print("[Shard World Index] Current generated session is missing; returning to stashed home world.")
                finish_interrupted_return_to_stored_world(index, state, cb)
            end
        end)
        return
    end

    local home = get_world_switch_home_state(state)
    if home ~= nil and home.session_id == session_id then
        print("[Shard World Index] Finishing interrupted return to stored world.")
        finish_interrupted_return_to_stored_world(index, state, cb)
        return
    end

    print("[Shard World Index] Clearing stale sidecar for unrelated session.")
    clear_world_switch_sidecar(index, cb)
end

local function read_named_world_switch_sidecar_in_slot(slot, file_id)
    if slot == nil or TheSim == nil then
        return nil, false
    end

    file_id = normalize_world_switch_file_id(file_id)
    local filename = "shardindex_"..file_id
    local state = nil
    local found = false
    TheSim:GetPersistentStringInClusterSlot(slot, "Master", filename, function(load_success, str)
        if load_success and str ~= nil and #str > 0 then
            found = true
            local success, data = RunInSandboxSafe(str)
            if success and type(data) == "table" then
                data.file_id = normalize_world_switch_file_id(data.file_id or file_id)
                state = ensure_world_switch_home_aliases(data)
            end
        end
    end)
    return state, found
end

local function read_world_switch_sidecar_in_slot(slot)
    local ids = get_known_world_switch_file_ids()
    for _, file_id in ipairs(ids) do
        local state = read_named_world_switch_sidecar_in_slot(slot, file_id)
        if world_switch_state_reserves_slot(state) then
            return state
        end
    end
end

local function read_active_world_switch_sidecar(slot)
    local state = read_world_switch_sidecar_in_slot(slot)
    return world_switch_state_reserves_slot(state) and state or nil
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
    index = resolve_index_args(self, index)
    return get_slot_and_shard(index)
end

function ShardWorldIndex:GetIndexShard(index)
    index = resolve_index_args(self, index)
    return get_index_shard(index)
end

function ShardWorldIndex:GetLevelForShard(level, shardid)
    return get_level_for_shard(level, shardid)
end

function ShardWorldIndex:ReadWorldgenOverrideRaw(index, cb)
    index, cb = resolve_index_args(self, index, cb)
    read_worldgenoverride_raw(index, cb)
end

function ShardWorldIndex:RestoreWorldgenOverride(index, raw, cb)
    index, raw, cb = resolve_index_args(self, index, raw, cb)
    restore_worldgenoverride(index, raw, cb)
end

function ShardWorldIndex:WriteLevelWorldgenOverride(index, level, cb)
    index, level, cb = resolve_index_args(self, index, level, cb)
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
    index, sessions, session_identifier, savedata, cb = resolve_index_args(self, index, sessions, session_identifier, savedata, cb)
    inject_player_sessions_into_world(index, sessions, session_identifier, savedata, cb)
end

function ShardWorldIndex:InjectPlayerSessionsIntoExistingWorld(index, session_id, sessions, cb, spawn_override)
    index, session_id, sessions, cb, spawn_override = resolve_index_args(self, index, session_id, sessions, cb, spawn_override)
    inject_player_sessions_into_existing_world(index, session_id, sessions, cb, spawn_override)
end

function ShardWorldIndex:WorldSessionExists(index, session_id, cb)
    index, session_id, cb = resolve_index_args(self, index, session_id, cb)
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

function ShardWorldIndex:GetSecondaryShardPlayerCounts()
    return get_secondary_shard_player_counts()
end

function ShardWorldIndex:WaitForSecondaryShardPlayersEmpty(cb, timeout, poll_interval)
    wait_for_secondary_shard_players_empty(cb, timeout, poll_interval)
end

function ShardWorldIndex:RestartCurrentSlotAfterShardRPC(index, extra_params)
    index, extra_params = resolve_index_args(self, index, extra_params)
    restart_current_slot_after_shard_rpc(index, extra_params)
end

function ShardWorldIndex:SwitchIndexToGeneratedWorld(index, level, keep_session)
    index, level, keep_session = resolve_index_args(self, index, level, keep_session)
    switch_index_to_generated_world(index, level, keep_session)
end

function ShardWorldIndex:SwitchIndexToExistingWorld(index, home)
    index, home = resolve_index_args(self, index, home)
    switch_index_to_existing_world(index, home)
end

function ShardWorldIndex:DeleteSessionIfNotHome(session_id, home_session_id)
    delete_session_if_not_home(session_id, home_session_id)
end

function ShardWorldIndex:GetState(index, file_id)
    index, file_id = resolve_index_args(self, index, file_id)
    return get_world_switch_state(index, file_id)
end

function ShardWorldIndex:SetState(index, state, file_id)
    index, state, file_id = resolve_index_args(self, index, state, file_id)
    set_world_switch_state(index, state, file_id)
end

function ShardWorldIndex:IsActive(index)
    index = resolve_index_args(self, index)
    local state = get_world_switch_state(index)
    return state ~= nil and state.active == true
end

function ShardWorldIndex:ReadSidecar(index, cb, file_id)
    index, cb, file_id = resolve_index_args(self, index, cb, file_id)
    read_world_switch_sidecar(index, cb, file_id)
end

function ShardWorldIndex:WriteSidecar(index, state, cb, file_id)
    index, state, cb, file_id = resolve_index_args(self, index, state, cb, file_id)
    write_world_switch_sidecar(index, state, cb, file_id)
end

function ShardWorldIndex:ClearSidecar(index, cb, file_id)
    index, cb, file_id = resolve_index_args(self, index, cb, file_id)
    clear_world_switch_sidecar(index, cb, file_id)
end

function ShardWorldIndex:ClearAllSidecars(index, cb)
    index, cb = resolve_index_args(self, index, cb)
    clear_all_world_switch_sidecars(index, cb)
end

function ShardWorldIndex:RestoreParentWorldSwitch(index, state, cb)
    index, state, cb = resolve_index_args(self, index, state, cb)
    restore_parent_world_switch(index, state, cb)
end

function ShardWorldIndex:LoadSidecar(index, cb, file_id)
    index, cb, file_id = resolve_index_args(self, index, cb, file_id)
    read_world_switch_sidecar(index, function(state)
        load_world_switch_sidecar_state(index, state, cb)
    end, file_id)
end

function ShardWorldIndex:NeedsGenerationOnLoad(index)
    index = resolve_index_args(self, index)
    return is_load_slot() and is_pending_world_generation_state(get_world_switch_state(index))
end

function ShardWorldIndex:ReservesSlot(index)
    index = resolve_index_args(self, index)
    local state = get_world_switch_state(index)
    return world_switch_state_reserves_slot(state) and not is_load_slot()
end

function ShardWorldIndex:PreservePendingGenerationOnDelete(index, save_options, cb)
    index, save_options, cb = resolve_index_args(self, index, save_options, cb)
    local state = get_world_switch_state(index)
    if save_options and
        state ~= nil and
        state.active and
        should_preserve_pending_world_generation(state) and
        not should_regenerate_current_world_switch_session(index, state) then
        local staged_world = deepcopy_safe(index.world)
        local staged_server = deepcopy_safe(index.server)
        local staged_enabled_mods = deepcopy_safe(index.enabled_mods)
        local staged_session_id = index:GetSession()
        local home = get_world_switch_home_state(state)
        if home ~= nil and home.session_id ~= nil and home.session_id ~= "" and
            (staged_session_id == nil or staged_session_id == "") then
            switch_index_to_existing_world(index, home)
        end

        index:MarkDirty()
        index:Save(function(...)
            local args = { ... }
            index.world = staged_world or { options = {} }
            index.server = staged_server or {}
            index.enabled_mods = staged_enabled_mods or {}
            index.session_id = staged_session_id
            index:MarkDirty()
            set_world_switch_state(index, state)
            write_world_switch_sidecar(index, state, function()
                if cb ~= nil then
                    cb(unpack(args))
                end
            end)
        end)
        return true
    end

    return false
end

function ShardWorldIndex:PrepareDelete(index, save_options, cb)
    index, save_options, cb = resolve_index_args(self, index, save_options, cb)
    local state = get_world_switch_state(index)
    if save_options and state ~= nil and state.active then
        if prepare_current_world_switch_regen(index, state, cb) then
            return
        end
        prepare_interrupted_world_switch_regen(index)
    end

    clear_all_world_switch_sidecars(index, cb)
end

function ShardWorldIndex:PrepareSetServerShardData(index, cb)
    index, cb = resolve_index_args(self, index, cb)
    local state = get_world_switch_state(index)
    if state ~= nil and state.active and not should_preserve_pending_world_generation(state) then
        prepare_interrupted_world_switch_regen(index)
        clear_interrupted_world_switch_transition(index, cb)
        return true
    end

    return false
end

function ShardWorldIndex:BeforeGenerateNewWorld(index, savedata, metadataStr, session_identifier)
    index, savedata, metadataStr, session_identifier = resolve_index_args(self, index, savedata, metadataStr, session_identifier)
    local state = get_world_switch_state(index)
    if state ~= nil and state.active then
        apply_pending_world_generation_state(state)
        local world_table = get_savedata_table(savedata)
        state.current_session_id = session_identifier
        state.updated_at = os.time()
        write_world_switch_topology_state(world_table, state)
        if type(savedata) == "string" and type(world_table) == "table" then
            savedata = DataDumper(world_table, nil, BRANCH ~= "dev")
        end
    end
    return savedata, metadataStr
end

function ShardWorldIndex:AfterGenerateNewWorld(index, savedata, session_identifier, cb)
    index, savedata, session_identifier, cb = resolve_index_args(self, index, savedata, session_identifier, cb)
    cb = cb or noop

    local state = get_world_switch_state(index)
    if state ~= nil and state.active then
        finish_generated_world_switch(index, state, session_identifier, savedata, false, cb)
        return
    end

    cb()
end

function ShardWorldIndex:BeginWorldSwitch(index, opts, cb)
    index, opts, cb = resolve_index_args(self, index, opts, cb)
    cb = cb or noop
    opts = opts or {}

    local active_state = get_world_switch_state(index)
    if active_state ~= nil and active_state.active == true then
        if opts.kind == "adventure" and active_state.kind ~= "adventure" then
            print("[Shard World Index] Suspending normal world switch before adventure.")
            suspend_current_world_switch_for_adventure(index, active_state, function(parent_state)
                opts = attach_parent_world_switch_for_adventure(opts, parent_state)
                self:BeginWorldSwitch(index, opts, cb)
            end)
            return
        end

        print("[Shard World Index] A world switch is already active.")
        cb(false)
        return
    end

    local home_session = index:GetSession()
    if home_session == nil or home_session == "" then
        print("[Shard World Index] Cannot switch without a current world session.")
        cb(false)
        return
    end

    local target = get_world_switch_target_from_opts(opts)
    if target == nil then
        print("[Shard World Index] Missing target world.")
        cb(false)
        return
    end
    local file_id = normalize_world_switch_file_id(opts.file_id or get_world_switch_target_file_id(target))

    read_worldgenoverride_raw(index, function(home_wgo)
        local state = deepcopy_safe(opts.state) or {}
        state.active = true
        state.file_id = normalize_world_switch_file_id(state.file_id or file_id)
        state.kind = state.kind or opts.kind or "world_switch"
        state.reuse_existing = opts.reuse_existing ~= false
        if opts.secondary == true then
            state.secondary = true
        end
        state.reason = state.reason or opts.reason or "begin"
        state.sequence_id = state.sequence_id or opts.sequence_id or "default"
        state.slot = state.slot or index:GetSlot()
        state.shard = state.shard or get_index_shard(index)
        state.started_at = state.started_at or os.time()
        state.updated_at = os.time()
        state.level_sequence = state.level_sequence or deepcopy_safe(opts.level_sequence)
        state.chapter = state.chapter or opts.chapter
        state.current_target = target
        state.current_preset = state.current_preset or get_world_switch_target_id(target)
        state.current_session_id = nil

        local is_secondary = state.secondary == true or opts.secondary == true
        local player_sessions = opts.player_sessions
        if player_sessions == nil and not is_secondary and opts.collect_player_sessions ~= false then
            player_sessions = collect_player_sessions()
        end
        opts.player_sessions = player_sessions
        state.player_sessions = state.player_sessions or player_sessions

        local home = state.home or state.main or build_world_switch_home_state(index, home_wgo, opts)
        state.home = home
        state.main = state.main or deepcopy_safe(home)

        commit_world_switch_target(index, state, target, opts.keep_session, cb)
    end)
end

function ShardWorldIndex:BeginSecondaryWorldSwitch(index, opts, cb)
    index, opts, cb = resolve_index_args(self, index, opts, cb)
    opts = opts or {}
    opts.secondary = true
    local state = deepcopy_safe(opts.state) or {}
    state.secondary = true
    opts.state = state
    self:BeginWorldSwitch(index, opts, cb)
end

function ShardWorldIndex:QueueNextWorld(index, opts, cb)
    index, opts, cb = resolve_index_args(self, index, opts, cb)
    cb = cb or noop
    opts = opts or {}

    local state = get_world_switch_state(index)
    if state == nil or not state.active or get_world_switch_home_state(state) == nil then
        print("[Shard World Index] No active world switch to advance.")
        cb(false)
        return
    end

    local target = get_world_switch_target_from_opts(opts, state)
    if target == nil and opts.chapter ~= nil and type(state.level_sequence) == "table" then
        target = normalize_world_switch_target(get_level_for_shard(state.level_sequence[opts.chapter], get_index_shard(index)))
    end
    if target == nil then
        print("[Shard World Index] Missing queued world.")
        cb(false)
        return
    end
    local current_file_id = normalize_world_switch_file_id(state.file_id)
    local queued_file_id = normalize_world_switch_file_id(opts.file_id or get_world_switch_target_file_id(target) or state.file_id)
    local previous_state = nil
    if queued_file_id ~= current_file_id then
        previous_state = deepcopy_safe(state)
        state = deepcopy_safe(state) or {}
    end
    state.file_id = queued_file_id

    local pending = deepcopy_safe(opts.pending_generation) or {}
    local player_sessions = pending.player_sessions or opts.player_sessions
    if player_sessions == nil and not state.secondary and opts.collect_player_sessions ~= false then
        player_sessions = collect_player_sessions()
    end
    pending.reason = pending.reason or opts.reason or "advance"
    pending.chapter = pending.chapter or opts.chapter
    pending.target = pending.target or target
    pending.current_target = pending.current_target or target
    pending.current_preset = pending.current_preset or get_world_switch_target_id(target)
    pending.file_id = pending.file_id or queued_file_id
    pending.player_sessions = player_sessions
    if pending.cleanup_session_id == nil and target.cleanup_on_return == true then
        pending.cleanup_session_id = state.current_session_id
    end
    pending.generation_source_session_id = pending.generation_source_session_id or state.current_session_id or index:GetSession()
    pending.generation_recovery_state = pending.generation_recovery_state or
        build_generation_recovery_state(index, state, pending.generation_source_session_id)
    pending.reuse_existing = opts.reuse_existing ~= false
    state.pending_generation = pending
    state.reuse_existing = opts.reuse_existing ~= false
    state.updated_at = os.time()

    local pending_chapter = pending.chapter

    local function finish_commit(success)
        if success and previous_state ~= nil then
            local parked_state = deepcopy_safe(previous_state)
            parked_state.active = false
            parked_state.pending_generation = nil
            parked_state.checked_existing_world = nil
            parked_state.updated_at = os.time()
            write_world_switch_sidecar(index, parked_state, function()
                set_world_switch_state(index, parked_state, current_file_id)
                set_world_switch_state(index, state, queued_file_id)
                cb(true, pending_chapter)
            end, current_file_id)
            return
        end

        if not success and previous_state ~= nil then
            write_world_switch_sidecar(index, nil, function()
                set_world_switch_state(index, nil, queued_file_id)
                set_world_switch_state(index, previous_state, current_file_id)
                cb(false, pending_chapter)
            end, queued_file_id)
            return
        end

        cb(success, pending_chapter)
    end

    local function commit_queued_state()
        apply_pending_world_generation_state(state)
        commit_world_switch_target(index, state, target, opts.keep_session, function(success)
            finish_commit(success)
        end)
    end

    if previous_state ~= nil then
        read_world_switch_sidecar(index, function(existing_state)
            state.current_session_id = nil
            state.current_worldgenoverride = nil
            state.current_world = nil
            state.current_server = nil
            state.current_enabled_mods = nil
            state.generated = nil
            state.generated_target = nil

            if existing_state ~= nil and existing_state.current_session_id ~= nil and existing_state.current_session_id ~= "" then
                state.current_session_id = existing_state.current_session_id
                state.current_preset = existing_state.current_preset or state.current_preset
                state.current_worldgenoverride = existing_state.current_worldgenoverride
                state.current_world = deepcopy_safe(existing_state.current_world)
                state.current_server = deepcopy_safe(existing_state.current_server)
                state.current_enabled_mods = deepcopy_safe(existing_state.current_enabled_mods)
                state.generated = existing_state.generated == true or nil
                state.generated_target = deepcopy_safe(existing_state.generated_target)
                state.world_type = existing_state.world_type or state.world_type
            end

            write_world_switch_sidecar(index, state, commit_queued_state)
        end, queued_file_id)
        return
    end

    write_world_switch_sidecar(index, state, commit_queued_state)
end

function ShardWorldIndex:ReturnToStoredWorld(index, reason, cb, player_sessions)
    index, reason, cb, player_sessions = resolve_index_args(self, index, reason, cb, player_sessions)
    cb = cb or noop

    local state = get_world_switch_state(index)
    local home = get_world_switch_home_state(state)
    if state == nil or not state.active or home == nil then
        print("[Shard World Index] No active world switch to return from.")
        cb(false)
        return
    end

    if should_cleanup_world_switch_session(state) then
        delete_session_if_not_home(state.current_session_id, home.session_id)
    end

    switch_index_to_existing_world(index, home)
    state.active = false
    state.finished_at = os.time()
    state.return_reason = reason or "return"

    local function save_return_state()
        restore_worldgenoverride(index, home.worldgenoverride, function()
            index:Save(function()
                write_world_switch_sidecar(index, state, function()
                    set_world_switch_state(index, state)
                    cb(true)
                end)
            end)
        end)
    end

    local sessions = player_sessions or state.return_player_sessions
    if sessions ~= nil and #sessions > 0 and TheNet ~= nil and TheNet:GetIsServer() then
        inject_player_sessions_into_existing_world(index, home.session_id, sessions, function()
            state.return_player_sessions = nil
            state.last_player_session_injected = home.session_id
            save_return_state()
        end, home.return_position)
        return
    end

    save_return_state()
end

function ShardWorldIndex:StartWorldSwitch(index, opts)
    index, opts = resolve_index_args(self, index, opts)
    if index == nil then
        return false
    end
    if TheShard ~= nil and not is_master_shard() then
        print("[Shard World Index] StartWorldSwitch must be called on the master shard.")
        return false
    end

    opts = opts or {}

    local function begin_after_save()
        if opts.kind ~= "adventure" and opts.player_sessions == nil and opts.collect_player_sessions ~= false then
            opts.player_sessions = collect_player_sessions()
        end
        self:BeginWorldSwitch(index, opts, function(success)
            if success then
                restart_current_slot_after_shard_rpc(index,
                {
                    world_switch_transition = opts.reason or "begin",
                    world_switch_file_id = get_world_switch_state(index) ~= nil and get_world_switch_state(index).file_id or opts.file_id,
                })
            end
        end)
    end

    if TheWorld ~= nil and TheWorld.ismastersim then
        if opts.force_players_to_master_modname ~= nil then
            send_force_players_to_master_rpc(opts.force_players_to_master_modname, opts.force_players_to_master_rpcname)
        end
        wait_for_secondary_shard_players_empty(function()
            index:SaveCurrent(begin_after_save)
        end, opts.secondary_shard_wait_timeout or nil, opts.secondary_shard_wait_poll_interval or nil)
    else
        save_players()
        begin_after_save()
    end
    return true
end

function ShardWorldIndex:AdvanceWorldSwitch(index, opts)
    index, opts = resolve_index_args(self, index, opts)
    if index == nil or not self:IsActive(index) then
        return false
    end
    if TheShard ~= nil and not is_master_shard() then
        print("[Shard World Index] AdvanceWorldSwitch must be called on the master shard.")
        return false
    end

    opts = opts or {}

    local function advance_after_save()
        self:QueueNextWorld(index, opts, function(success)
            if success then
                restart_current_slot_after_shard_rpc(index,
                {
                    world_switch_transition = opts.reason or "advance",
                    world_switch_file_id = get_world_switch_state(index) ~= nil and get_world_switch_state(index).file_id or opts.file_id,
                })
            end
        end)
    end

    if TheWorld ~= nil and TheWorld.ismastersim then
        wait_for_secondary_shard_players_empty(function()
            save_players()
            advance_after_save()
        end, opts.secondary_shard_wait_timeout or nil, opts.secondary_shard_wait_poll_interval or nil)
    else
        save_players()
        advance_after_save()
    end
    return true
end

function ShardWorldIndex:ReturnFromWorldSwitch(index, reason)
    index, reason = resolve_index_args(self, index, reason)
    if index == nil or not self:IsActive(index) then
        return false
    end

    local function return_after_save()
        save_players()
        local player_sessions = collect_player_sessions()
        self:ReturnToStoredWorld(index, reason or "return", function(success)
            if success then
                restart_current_slot_after_shard_rpc(index, { world_switch_transition = reason or "return" })
            end
        end, player_sessions)
    end

    if TheWorld ~= nil and TheWorld.ismastersim then
        wait_for_secondary_shard_players_empty(return_after_save)
    else
        return_after_save()
    end
    return true
end

function ShardWorldIndex:HasActiveSidecar(slot)
    return read_active_world_switch_sidecar(slot) ~= nil
end

function ShardWorldIndex:ReadActiveSidecar(slot)
    return read_active_world_switch_sidecar(slot)
end

function ShardWorldIndex:SwitchIndexToStoredWorld(index, state)
    index, state = resolve_index_args(self, index, state)
    local home = get_world_switch_home_state(state)
    if home ~= nil then
        switch_index_to_existing_world(index, home)
        return true
    end
    return false
end
