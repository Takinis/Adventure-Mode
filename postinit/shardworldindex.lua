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
local DEFAULT_VOLCANO_LEVEL =
{
    world_type = "volcano",
    location = "volcano",
}
local PORKLAND_SECONDARY_LEVEL =
{
    world_type = "cave",
    location = "cave",
    worldgen_preset = "HAMLET_SECONDARY",
    settings_preset = "DST_CAVE",
    overrides =
    {
        task_set = "HAMLET_SECONDARY",
        start_location = "HamletSecondaryStart",
        world_size = "small",
        layout_mode = "LinkNodesByKeys",
        roads = "never",
        boons = "never",
        has_ocean = false,
        keep_disconnected_tiles = true,
        no_wormholes_to_disconnected_tiles = true,
        no_joining_islands = true,
    },
}

local function noop()
end

local function save_index(index, cb)
    cb = cb or noop
    index:Save(function(success)
        if success ~= true and index.MarkDirty ~= nil then
            index:MarkDirty()
        end
        cb(success == true)
    end)
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

local function get_runtime_shard_id(index)
    local shardid = TheShard ~= nil and TheShard.GetShardId ~= nil and TheShard:GetShardId() or nil
    if shardid ~= nil and shardid ~= "" then
        return shardid
    end

    shardid = get_index_shard(index)
    return is_master_shard_id(shardid) and SHARDID.MASTER or shardid
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

    local function onwrite(success)
        cb(success == true)
    end

    local slot, shard = get_slot_and_shard(index)
    if slot ~= nil and shard ~= nil then
        TheSim:SetPersistentStringInClusterSlot(slot, shard, WORLDGENOVERRIDE_FILE, str, false, onwrite)
    else
        TheSim:SetPersistentString(WORLDGENOVERRIDE_FILE, str, false, onwrite)
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

local function get_current_session_id()
    local session_id = TheWorld ~= nil and TheWorld.meta ~= nil and TheWorld.meta.session_identifier or nil
    return type(session_id) == "string" and session_id ~= "" and session_id or nil
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
                    origin_session_id = session.origin_session_id,
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
                origin_session_id = get_current_session_id(),
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
        origin_session_id = get_current_session_id(),
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

    return
    {
        x = x,
        y = y or 0,
        z = z,
        puid = pos.puid,
        rx = tonumber(pos.rx),
        ry = tonumber(pos.ry),
        rz = tonumber(pos.rz),
    }
end

local function get_player_positions(sessions)
    local positions = {}
    for _, session in ipairs(sessions or {}) do
        if session.userid ~= nil and session.userid ~= "" and type(session.data) == "string" then
            local success, data = RunInSandboxSafe(session.data)
            local position = success and normalize_position(data) or nil
            if position ~= nil then
                positions[session.userid] = position
            end
        end
    end
    return next(positions) ~= nil and positions or nil
end

local function merge_player_positions(existing, updates)
    local positions = deepcopy_safe(existing) or {}
    for userid, position in pairs(updates or {}) do
        positions[userid] = deepcopy_safe(position)
    end
    return next(positions) ~= nil and positions or nil
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

local function get_prefab_position_from_savedata_str(savedata, prefab)
    if type(savedata) ~= "string" or #savedata <= 0 or type(prefab) ~= "string" or prefab == "" then
        return nil
    end

    local success, world = RunInSandboxSafe(savedata)
    local ents = success and world ~= nil and world.ents ~= nil and world.ents[prefab] or nil
    if ents ~= nil and ents[1] ~= nil then
        return
        {
            x = ents[1].x or 0,
            y = ents[1].y or 0,
            z = ents[1].z or 0,
        }
    end
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

local function move_player_record_to_spawn(data, spawn, spawn_index, origin_session_id, destination_session_id, shard_index)
    if type(data) ~= "table" then
        return nil
    end

    local offset = (spawn_index or 1) - 1
    local radius = offset > 0 and math.min(2 + offset, 8) or 0
    local angle = offset * 2.399963229728653

    data.x = (spawn.x or 0) + math.cos(angle) * radius
    data.y = spawn.y
    data.z = (spawn.z or 0) + math.sin(angle) * radius

    data.puid = spawn.puid
    data.rx = spawn.rx
    data.ry = spawn.ry
    data.rz = spawn.rz

    if type(data.data) == "table" then
        local migration = type(data.data.migration) == "table" and data.data.migration or nil
        origin_session_id = origin_session_id or (migration ~= nil and migration.sessionid or nil)
        if type(origin_session_id) == "string" and origin_session_id ~= "" and
            origin_session_id ~= destination_session_id then
            -- The origin session lets the engine remap persisted item skin IDs.
            data.data.migration =
            {
                worldid = get_runtime_shard_id(shard_index),
                sessionid = origin_session_id,
            }
        else
            data.data.migration = nil
        end
    end

    return data
end

local function build_migrated_user_session_data(session, spawn, spawn_index, destination_session_id, shard_index)
    local success, data = RunInSandboxSafe(session.data or "")
    if not success or type(data) ~= "table" or data.prefab == nil then
        return session.data
    end

    move_player_record_to_spawn(
        data,
        spawn,
        spawn_index,
        session.origin_session_id,
        destination_session_id,
        shard_index
    )
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
            local data = build_migrated_user_session_data(session, spawn, i, session_identifier, index)
            TheNet:SerializeUserSession(session.userid, data, false, get_player_classified_entity(session.userid), session.metadata or "")
        end
    end

    cb()
end

local function inject_player_sessions_into_existing_world(index, session_id, sessions, cb, spawn_override, player_positions, spawn_prefab)
    cb = cb or noop

    if session_id == nil or session_id == "" or sessions == nil or #sessions <= 0 or not TheNet:GetIsServer() then
        cb()
        return
    end

    read_world_session_raw(index, session_id, function(savedata)
        local spawn = get_prefab_position_from_savedata_str(savedata, spawn_prefab) or
            normalize_position(spawn_override) or get_spawn_position_from_savedata_str(savedata)
        TheNet:BeginSession(session_id)
        for i, session in ipairs(sessions) do
            local saved_position = player_positions ~= nil and normalize_position(player_positions[session.userid]) or nil
            local data = build_migrated_user_session_data(
                session,
                saved_position or spawn,
                saved_position ~= nil and 1 or i,
                session_id,
                index
            )
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

local secondary_world_index_request_serial = 0
local pending_secondary_world_index_request = nil
local prepared_secondary_world_index_requests = {}

local function get_secondary_shard_ids()
    local shardids = {}
    if ShardList == nil or TheShard == nil then
        return shardids
    end

    local self_shard = tostring(TheShard:GetShardId())
    local master_shard = tostring(SHARDID.MASTER)
    for shardid in pairs(ShardList) do
        shardid = shardid ~= nil and tostring(shardid) or nil
        if shardid ~= nil and shardid ~= self_shard and shardid ~= master_shard then
            table.insert(shardids, shardid)
        end
    end
    table.sort(shardids, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return shardids
end

local function send_secondary_world_index_abort(request)
    if request == nil then
        return
    end

    local rpc = GetShardModRPC("AdventureMode", "AbortSecondaryWorldIndex")
    if rpc == nil then
        return
    end
    for _, shardid in ipairs(request.shardids or {}) do
        local prepared = request.prepared ~= nil and request.prepared[shardid] or nil
        SendModRPCToShard(rpc, shardid, ZipAndEncodeString({
            request_id = request.id,
            operation = request.operation,
            file_id = prepared ~= nil and prepared.file_id or nil,
        }))
    end
    prepared_secondary_world_index_requests[request.id] = nil
end

local function finish_secondary_world_index_request(request, success)
    if pending_secondary_world_index_request ~= request then
        return
    end

    pending_secondary_world_index_request = nil
    if request.timeout_task ~= nil then
        request.timeout_task:Cancel()
        request.timeout_task = nil
    end
    local cb = request.cb or noop
    local should_abort = false
    local should_finalize = false
    if request.phase == "prepare" and success then
        prepared_secondary_world_index_requests[request.id] = request
    elseif request.phase == "prepare" then
        should_abort = true
    elseif request.phase == "commit" then
        prepared_secondary_world_index_requests[request.id] = nil
        should_finalize = success
        should_abort = not success
    end

    local function finish()
        if should_abort then
            send_secondary_world_index_abort(request)
        elseif should_finalize then
            local rpc = GetShardModRPC("AdventureMode", "FinalizeSecondaryWorldIndex")
            if rpc ~= nil then
                for _, shardid in ipairs(request.shardids or {}) do
                    local prepared = request.prepared ~= nil and request.prepared[shardid] or nil
                    SendModRPCToShard(rpc, shardid, ZipAndEncodeString({
                        request_id = request.id,
                        operation = request.operation,
                        file_id = prepared ~= nil and prepared.file_id or nil,
                    }))
                end
            end
        end
        cb(success, success and request or nil)
    end
    if TheWorld ~= nil then
        TheWorld:DoStaticTaskInTime(0, finish)
    else
        finish()
    end
end

local function request_secondary_world_index(name, data, cb, timeout)
    cb = cb or noop
    if not is_master_shard() or SendModRPCToShard == nil or GetShardModRPC == nil or TheWorld == nil then
        print("[Shard World Index] Cannot request secondary WorldIndex preparation from this shard.")
        cb(false)
        return false
    end
    if pending_secondary_world_index_request ~= nil or next(prepared_secondary_world_index_requests) ~= nil then
        print("[Shard World Index] Another secondary WorldIndex request is still pending.")
        cb(false)
        return false
    end

    local shardids = get_secondary_shard_ids()
    if #shardids == 0 then
        cb(true, nil)
        return true
    end

    local rpc = GetShardModRPC("AdventureMode", name)
    if rpc == nil then
        print("[Shard World Index] Missing shard RPC for "..tostring(name)..".")
        cb(false)
        return false
    end

    secondary_world_index_request_serial = secondary_world_index_request_serial + 1
    local request_id = table.concat({ tostring(TheShard:GetShardId()), tostring(os.time()), tostring(secondary_world_index_request_serial) }, ":")
    local payload_data = deepcopy_safe(data) or {}
    payload_data.request_id = request_id

    local request =
    {
        id = request_id,
        operation = name,
        phase = "prepare",
        shardids = shardids,
        waiting = {},
        prepared = {},
        cb = cb,
    }
    for _, shardid in ipairs(shardids) do
        request.waiting[shardid] = true
    end
    pending_secondary_world_index_request = request

    request.timeout_task = TheWorld:DoStaticTaskInTime(timeout or SECONDARY_SHARD_WAIT_TIMEOUT, function()
        request.timeout_task = nil
        if pending_secondary_world_index_request ~= request then
            return
        end

        local missing = {}
        for shardid in pairs(request.waiting) do
            table.insert(missing, tostring(shardid))
        end
        table.sort(missing)
        print("[Shard World Index] Timed out waiting for "..tostring(name).." replies from shards: "..table.concat(missing, ", ")..".")
        finish_secondary_world_index_request(request, false)
    end)

    local payload = ZipAndEncodeString(payload_data)
    for _, shardid in ipairs(shardids) do
        print("[Shard World Index] Requesting "..tostring(name).." from shard "..tostring(shardid).." ("..request_id..").")
        SendModRPCToShard(rpc, shardid, payload)
    end
    return true
end

local function commit_secondary_world_index_request(request, cb, timeout)
    cb = cb or noop
    if request == nil then
        cb(true)
        return true
    end
    if prepared_secondary_world_index_requests[request.id] ~= request or pending_secondary_world_index_request ~= nil then
        cb(false)
        return false
    end

    local rpc = GetShardModRPC("AdventureMode", "CommitSecondaryWorldIndex")
    if rpc == nil then
        send_secondary_world_index_abort(request)
        cb(false)
        return false
    end

    request.phase = "commit"
    request.cb = cb
    request.waiting = {}
    for _, shardid in ipairs(request.shardids) do
        request.waiting[shardid] = true
    end
    pending_secondary_world_index_request = request
    request.timeout_task = TheWorld:DoStaticTaskInTime(timeout or SECONDARY_SHARD_WAIT_TIMEOUT, function()
        request.timeout_task = nil
        if pending_secondary_world_index_request ~= request then
            return
        end
        local missing = {}
        for shardid in pairs(request.waiting) do
            table.insert(missing, tostring(shardid))
        end
        table.sort(missing)
        print("[Shard World Index] Timed out waiting for commit replies from shards: "..table.concat(missing, ", ")..".")
        finish_secondary_world_index_request(request, false)
    end)

    for _, shardid in ipairs(request.shardids) do
        local prepared = request.prepared[shardid]
        SendModRPCToShard(rpc, shardid, ZipAndEncodeString({
            request_id = request.id,
            operation = request.operation,
            file_id = prepared ~= nil and prepared.file_id or nil,
        }))
    end
    return true
end

local function abort_secondary_world_index_request(request)
    if request == nil then
        return
    end
    if pending_secondary_world_index_request == request then
        pending_secondary_world_index_request = nil
        if request.timeout_task ~= nil then
            request.timeout_task:Cancel()
            request.timeout_task = nil
        end
    end
    send_secondary_world_index_abort(request)
end

local function handle_secondary_world_index_reply(shardid, data)
    local request = pending_secondary_world_index_request
    shardid = shardid ~= nil and tostring(shardid) or nil
    if request == nil or type(data) ~= "table" or data.request_id ~= request.id or
        data.operation ~= request.operation or data.phase ~= request.phase or request.waiting[shardid] ~= true then
        return false
    end

    if data.success ~= true then
        print("[Shard World Index] Shard "..tostring(shardid).." failed during "..tostring(request.phase)..
            " for "..tostring(request.operation)..".")
        finish_secondary_world_index_request(request, false)
        return true
    end

    request.waiting[shardid] = nil
    if request.phase == "prepare" then
        request.prepared[shardid] = { file_id = data.file_id }
    end
    print("[Shard World Index] Shard "..tostring(shardid).." completed "..tostring(request.phase)..
        " for "..tostring(request.operation).." ("..request.id..").")
    if next(request.waiting) == nil then
        finish_secondary_world_index_request(request, true)
    end
    return true
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
        cb(true)
        return
    end

    timeout = timeout or SECONDARY_SHARD_WAIT_TIMEOUT
    poll_interval = poll_interval or SECONDARY_SHARD_WAIT_POLL_INTERVAL

    local started_at = GetTime()
    local function poll()
        local secondary_players = get_secondary_shard_player_counts()

        if secondary_players <= 0 then
            TheWorld:DoTaskInTime(SECONDARY_SHARD_SETTLE_DELAY, function()
                cb(true)
            end)
            return
        end

        if GetTime() - started_at >= timeout then
            print("[Shard World Index] Timed out waiting for secondary shard players to return to master. Remaining secondary players: "..tostring(secondary_players))
            cb(false)
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
        -- Let queued shard RPCs leave this process before StartNextInstance shuts it down.
        TheWorld:DoStaticTaskInTime(SECONDARY_SHARD_SETTLE_DELAY, function()
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

local function get_savedata_world_type(savedata)
    local data = get_savedata_table(savedata)
    local map = data ~= nil and data.map or nil
    return normalize_world_type(map ~= nil and map.prefab or nil)
end

local function read_world_session_world_type(index, session_id, cb)
    read_world_session_raw(index, session_id, function(savedata)
        cb(savedata ~= nil and get_savedata_world_type(savedata) or nil, savedata ~= nil)
    end)
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
        local secondary_level = level.secondary or level.cave or level.caves or level.placeholder
        if secondary_level ~= nil then
            return secondary_level
        end

        local world_type = normalize_world_type(level.world_type or level.location or level.dlc or level.mode)
        if world_type == "shipwrecked" then
            return DEFAULT_VOLCANO_LEVEL
        elseif world_type == "porkland" then
            return PORKLAND_SECONDARY_LEVEL
        elseif world_type == "cave" or world_type == "volcano" then
            return level
        end
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

local function resolve_level_world_type(level)
    local world_type = get_level_world_type(level)
    if world_type ~= nil then
        return world_type
    end

    local preset_id = get_worldgen_preset_id(level)
    if preset_id == nil then
        return nil
    end

    return get_level_world_type(find_level_data_by_id(require("map/levels"), preset_id))
end

local function get_stored_world_type(stored_world)
    if type(stored_world) ~= "table" then
        return nil
    end

    local world_type = normalize_world_type(stored_world.world_type)
    if world_type ~= nil then
        return world_type
    end

    local world = stored_world.world
    world_type = resolve_level_world_type(type(world) == "table" and world.options or nil)
    if world_type ~= nil then
        return world_type
    end

    return resolve_level_world_type(get_savedata_table(stored_world.worldgenoverride))
end

local function get_stored_world_preset(stored_world)
    if type(stored_world) ~= "table" then
        return nil
    end

    local preset = get_worldgen_preset_id(stored_world.current_preset)
    if preset ~= nil then
        return preset
    end

    local world = stored_world.world
    preset = get_worldgen_preset_id(type(world) == "table" and world.options or nil)
    if preset ~= nil then
        return preset
    end

    return get_worldgen_preset_id(get_savedata_table(stored_world.worldgenoverride))
end

local function get_runtime_world_type()
    if TheWorld == nil then
        return nil
    end

    for _, world_type in ipairs({ "porkland", "volcano", "shipwrecked", "cave", "forest" }) do
        if TheWorld:HasTag(world_type) then
            return world_type
        end
    end

    local prefab = normalize_world_type(TheWorld.prefab)
    for _, world_type in pairs(WORLD_TYPE_LOCATION) do
        if prefab == world_type then
            return world_type
        end
    end
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

local function validate_world_index_generated_level(level)
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

local ADVENTURE_WORLD_INDEX_FILE_ID = "adventure"
local WORLD_INDEX_KNOWN_FILE_IDS =
{
    Master =
    {
        "forest",
        "shipwrecked",
        "porkland",
    },
    Caves =
    {
        "caves",
        "volcano",
    },
}
local SECONDARY_WORLD_INDEX_FILE_IDS =
{
    forest = "caves",
    cave = "caves",
    caves = "caves",
    shipwrecked = "volcano",
    volcano = "volcano",
    porkland = "caves",
}

local function normalize_world_index_file_id(file_id)
    if file_id == nil or file_id == "" then
        return "world"
    end

    file_id = string.lower(tostring(file_id)):gsub("[^%w_%-]", "_")
    file_id = file_id:gsub("_+", "_"):gsub("^_+", ""):gsub("_+$", "")
    return file_id ~= "" and file_id or "world"
end

local function add_world_index_file_id(list, seen, file_id)
    file_id = normalize_world_index_file_id(file_id)
    if not seen[file_id] then
        seen[file_id] = true
        table.insert(list, file_id)
    end
end

local function get_world_index_file_id_for_shard(file_id, shardid)
    file_id = normalize_world_index_file_id(file_id)
    return not is_master_shard_id(shardid) and SECONDARY_WORLD_INDEX_FILE_IDS[file_id] or file_id
end

local function is_known_world_index_file_id(file_id, shardid)
    if file_id == ADVENTURE_WORLD_INDEX_FILE_ID then
        return true
    end

    local known_ids = is_master_shard_id(shardid) and WORLD_INDEX_KNOWN_FILE_IDS.Master or WORLD_INDEX_KNOWN_FILE_IDS.Caves
    for _, known_file_id in ipairs(known_ids) do
        if file_id == known_file_id then
            return true
        end
    end
    return false
end

local function get_known_world_index_file_ids(index, extra_file_id)
    local ids = {}
    local seen = {}
    local shardid = index ~= nil and get_index_shard(index) or "Master"

    local function add_known_file_id(file_id)
        file_id = get_world_index_file_id_for_shard(file_id, shardid)
        if is_known_world_index_file_id(file_id, shardid) then
            add_world_index_file_id(ids, seen, file_id)
        end
    end

    if extra_file_id ~= nil then
        add_known_file_id(extra_file_id)
    end
    if Settings ~= nil and Settings.world_index_file_id ~= nil then
        add_known_file_id(Settings.world_index_file_id)
    end
    add_world_index_file_id(ids, seen, ADVENTURE_WORLD_INDEX_FILE_ID)

    local known_ids = is_master_shard_id(shardid) and WORLD_INDEX_KNOWN_FILE_IDS.Master or WORLD_INDEX_KNOWN_FILE_IDS.Caves
    for _, file_id in ipairs(known_ids) do
        add_world_index_file_id(ids, seen, file_id)
    end

    return ids
end

local function get_world_index_home_state(state)
    return state ~= nil and (state.home or state.main) or nil
end

local function set_player_positions_for_session(state, session_id, player_positions)
    if state == nil then
        return
    end

    state.player_positions = merge_player_positions(state.player_positions, player_positions)
    local home = get_world_index_home_state(state)
    if home ~= nil and home.session_id == session_id then
        home.player_positions = merge_player_positions(home.player_positions, player_positions)
        if state.main ~= nil then
            state.main.player_positions = merge_player_positions(state.main.player_positions, player_positions)
        end
    end
end

local function ensure_world_index_home_aliases(state)
    if state ~= nil then
        state.file_id = normalize_world_index_file_id(state.file_id)
        if state.home == nil and state.main ~= nil then
            state.home = state.main
        elseif state.main == nil and state.home ~= nil then
            state.main = state.home
        end
        if state.home ~= nil and state.home.player_positions == nil then
            state.home.player_positions = get_player_positions(state.home.player_sessions)
        end
        if state.main ~= nil and state.main.player_positions == nil then
            state.main.player_positions = get_player_positions(state.main.player_sessions)
        end
    end
    return state
end

local function world_index_state_reserves_slot(state)
    ensure_world_index_home_aliases(state)
    local home = get_world_index_home_state(state)
    return state ~= nil and
        state.active == true and
        home ~= nil and
        home.session_id ~= nil and
        home.session_id ~= ""
end

local function world_index_state_matches_current_session(index, state)
    local session_id = index ~= nil and index.GetSession ~= nil and index:GetSession() or nil
    return session_id ~= nil and
        session_id ~= "" and
        state ~= nil and
        state.current_session_id == session_id
end

local function get_world_index_sidecar_filename(index, file_id)
    return index:GetShardIndexName().."_"..normalize_world_index_file_id(file_id)
end

local function read_named_world_index_sidecar(index, file_id, cb)
    cb = cb or noop
    file_id = normalize_world_index_file_id(file_id)

    local filename = get_world_index_sidecar_filename(index, file_id)
    local slot, shard = get_slot_and_shard(index)
    local function onload(load_success, str)
        if load_success and str ~= nil and #str > 0 then
            local success, data = RunInSandboxSafe(str)
            if success and type(data) == "table" then
                data.file_id = normalize_world_index_file_id(data.file_id or file_id)
                ensure_world_index_home_aliases(data)
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

local function read_world_index_sidecar(index, cb, file_id)
    cb = cb or noop

    if file_id ~= nil then
        read_named_world_index_sidecar(index, file_id, function(state)
            cb(state)
        end)
        return
    end

    local ids = get_known_world_index_file_ids(index, index.world_index_state ~= nil and index.world_index_state.file_id or nil)
    local active_state = nil
    local active_state_matches_session = false
    local return_recovery_state = nil
    local i = 1

    local function read_next()
        if i > #ids then
            cb(active_state or return_recovery_state)
            return
        end

        local current_file_id = ids[i]
        i = i + 1
        read_named_world_index_sidecar(index, current_file_id, function(state)
            if state ~= nil and state.active == true then
                local matches_session = world_index_state_matches_current_session(index, state)
                if active_state == nil or
                    (matches_session and not active_state_matches_session) or
                    (not active_state_matches_session and active_state.kind ~= "adventure" and state.kind == "adventure") then
                    active_state = state
                    active_state_matches_session = matches_session
                end
            elseif state ~= nil and type(state.return_pending) == "table" and
                type(state.parent_world_index_state) == "table" then
                return_recovery_state = return_recovery_state or state
            end
            read_next()
        end)
    end

    read_next()
end

local function write_world_index_sidecar(index, data, cb, file_id)
    cb = cb or noop
    file_id = normalize_world_index_file_id(file_id or (data ~= nil and data.file_id or nil))

    ensure_world_index_home_aliases(data)
    if data ~= nil then
        data.file_id = file_id
    end

    local filename = get_world_index_sidecar_filename(index, file_id)
    local slot, shard = get_slot_and_shard(index)
    local function onwrite(success)
        cb(success == true)
    end
    if data == nil then
        if slot ~= nil and shard ~= nil then
            -- Cluster-slot saves do not expose a Lua erase API; empty data is treated as cleared.
            TheSim:SetPersistentStringInClusterSlot(slot, shard, filename, "", false, onwrite)
        elseif ErasePersistentString ~= nil then
            ErasePersistentString(filename, onwrite)
        else
            TheSim:SetPersistentString(filename, "", false, onwrite)
        end
        return
    end

    local str = DataDumper(data, nil, false)
    if slot ~= nil and shard ~= nil then
        TheSim:SetPersistentStringInClusterSlot(slot, shard, filename, str, false, onwrite)
    else
        TheSim:SetPersistentString(filename, str, false, onwrite)
    end
end

local function get_world_index_state_map(index)
    index.world_index_states = index.world_index_states or {}
    return index.world_index_states
end

local function set_world_index_state(index, state, file_id)
    if index == nil then
        return
    end

    file_id = normalize_world_index_file_id(file_id or (state ~= nil and state.file_id or nil))
    local states = get_world_index_state_map(index)
    if state ~= nil then
        state.file_id = file_id
        states[file_id] = ensure_world_index_home_aliases(state)
        if index.world_index_state == nil or state.active == true or
            normalize_world_index_file_id(index.world_index_state.file_id) == file_id then
            index.world_index_state = states[file_id]
        end
    else
        states[file_id] = nil
        if index.world_index_state ~= nil and
            normalize_world_index_file_id(index.world_index_state.file_id) == file_id then
            index.world_index_state = nil
            for _, stored_state in pairs(states) do
                if stored_state.active == true then
                    index.world_index_state = stored_state
                    break
                end
            end
        end
    end
end

local function get_world_index_state(index, file_id)
    if index == nil then
        return nil
    end

    if file_id ~= nil then
        file_id = normalize_world_index_file_id(file_id)
        local states = index.world_index_states
        if states ~= nil and states[file_id] ~= nil then
            return ensure_world_index_home_aliases(states[file_id])
        end
        if index.world_index_state ~= nil and normalize_world_index_file_id(index.world_index_state.file_id) == file_id then
            return ensure_world_index_home_aliases(index.world_index_state)
        end
        return nil
    end

    local current_state = ensure_world_index_home_aliases(index.world_index_state)
    if current_state ~= nil and
        current_state.active == true and
        world_index_state_matches_current_session(index, current_state) then
        return current_state
    end

    local states = index.world_index_states
    if states ~= nil then
        for _, state in pairs(states) do
            if state.active == true and world_index_state_matches_current_session(index, state) then
                index.world_index_state = state
                return ensure_world_index_home_aliases(state)
            end
        end
    end

    if current_state ~= nil and current_state.active == true then
        return current_state
    end

    if states ~= nil then
        for _, state in pairs(states) do
            if state.active == true then
                index.world_index_state = state
                return ensure_world_index_home_aliases(state)
            end
        end
    end

    return current_state
end

local function clear_world_index_sidecar(index, cb, file_id)
    file_id = normalize_world_index_file_id(file_id or (get_world_index_state(index) ~= nil and get_world_index_state(index).file_id or nil))
    write_world_index_sidecar(index, nil, function(success)
        if success then
            set_world_index_state(index, nil, file_id)
        end
        (cb or noop)(success)
    end, file_id)
end

local function clear_all_world_index_sidecars(index, cb)
    cb = cb or noop
    local ids = get_known_world_index_file_ids(index, index.world_index_state ~= nil and index.world_index_state.file_id or nil)
    local i = 1

    local function clear_next(success)
        if success == false then
            cb(false)
            return
        end
        if i > #ids then
            index.world_index_states = {}
            index.world_index_state = nil
            cb(true)
            return
        end

        local file_id = ids[i]
        i = i + 1
        write_world_index_sidecar(index, nil, clear_next, file_id)
    end

    clear_next()
end

local function is_world_index_transition_restart()
    return Settings ~= nil and
        Settings.reset_action == RESET_ACTION.LOAD_SLOT and
        (Settings.world_index_transition ~= nil or Settings.adventure_transition ~= nil)
end

local function is_load_slot()
    return Settings ~= nil and Settings.reset_action == RESET_ACTION.LOAD_SLOT
end

local function is_pending_world_generation_state(state)
    local home = get_world_index_home_state(state)
    return state ~= nil and
        state.active == true and
        home ~= nil and
        home.session_id ~= nil and
        home.session_id ~= "" and
        (type(state.pending_generation) == "table" or
        ((state.current_session_id == nil or state.current_session_id == "") and (state.current_preset ~= nil or state.current_target ~= nil)))
end

local function should_preserve_pending_world_generation(state)
    return is_world_index_transition_restart() or
        is_pending_world_generation_state(state)
end

local function prepare_interrupted_world_index_regen(index)
    index.world = { options = {} }
    index.server = {}
    index.enabled_mods = {}
    index.session_id = nil
    index:MarkDirty()
end

local function clear_interrupted_world_index_transition(index, cb)
    cb = cb or noop
    clear_world_index_sidecar(index, function(sidecar_cleared)
        if not sidecar_cleared then
            cb(false)
            return
        end
        restore_worldgenoverride(index, nil, cb)
    end)
end

local function world_index_state_has_origin(state)
    return state ~= nil and (state.slot ~= nil or state.shard ~= nil)
end

local function world_index_state_matches_index(index, state)
    if state == nil then
        return false
    end
    if state.slot ~= nil and state.slot ~= index:GetSlot() then
        return false
    end
    return state.shard == nil or state.shard == get_index_shard(index)
end

local function build_world_index_home_state(index, worldgenoverride, opts)
    opts = opts or {}
    local home = {
        session_id = opts.session_id or index:GetSession(),
        worldgenoverride = worldgenoverride,
        world = deepcopy_safe(index.world),
        server = deepcopy_safe(index.server),
        enabled_mods = deepcopy_safe(index.enabled_mods),
        return_position = opts.return_position or get_return_position(),
        player_sessions = opts.player_sessions,
        player_positions = get_player_positions(opts.player_sessions),
    }
    home.world_type = get_runtime_world_type() or get_stored_world_type(home)
    home.current_preset = get_stored_world_preset(home)
    return home
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

local restore_parent_world_index

local function finish_interrupted_return_to_stored_world(index, state, cb)
    cb = cb or noop

    local home = get_world_index_home_state(state)
    if home == nil or home.session_id == nil or home.session_id == "" then
        clear_world_index_sidecar(index, cb)
        return
    end

    state.active = false
    state.finished_at = state.finished_at or os.time()
    state.return_reason = state.return_reason or "interrupted_return"

    switch_index_to_existing_world(index, home)

    restore_worldgenoverride(index, home.worldgenoverride, function(worldgenoverride_saved)
        if not worldgenoverride_saved then
            cb(false)
            return
        end
        save_index(index, function(index_saved)
            if not index_saved then
                cb(false)
                return
            end
            write_world_index_sidecar(index, state, function(sidecar_saved)
                if not sidecar_saved then
                    cb(false)
                    return
                end
                set_world_index_state(index, state)
                local cleanup_session_id = type(state.return_pending) == "table" and
                    state.return_pending.cleanup_session_id or nil
                if cleanup_session_id ~= nil and cleanup_session_id ~= "" then
                    delete_session_if_not_home(cleanup_session_id, home.session_id)
                end
                restore_parent_world_index(index, state, cb)
            end)
        end)
    end)
end

local function suspend_current_world_index_for_adventure(index, state, cb)
    cb = cb or noop
    state = ensure_world_index_home_aliases(state)

    if state == nil or state.active ~= true then
        cb(nil, true)
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
    local suspended_state = deepcopy_safe(state)
    suspended_state.active = false
    suspended_state.suspend_reason = "adventure_begin"
    suspended_state.suspended_at = os.time()
    suspended_state.updated_at = os.time()

    write_world_index_sidecar(index, suspended_state, function(success)
        if not success then
            cb(nil, false)
            return
        end
        set_world_index_state(index, suspended_state)
        cb(parent_state, true)
    end, suspended_state.file_id)
end

local function attach_parent_world_index_for_adventure(opts, parent_state)
    if opts == nil or parent_state == nil then
        return opts
    end

    opts.state = deepcopy_safe(opts.state) or {}
    opts.state.parent_world_index_state = deepcopy_safe(parent_state)

    return opts
end

restore_parent_world_index = function(index, state, cb)
    cb = cb or noop

    local parent_state = type(state) == "table" and state.parent_world_index_state or nil
    if type(parent_state) ~= "table" then
        if type(state) == "table" and state.return_pending ~= nil then
            state.return_pending = nil
            write_world_index_sidecar(index, state, function(saved)
                cb(saved == true)
            end, state.file_id)
            return
        end
        cb(true)
        return
    end

    parent_state = ensure_world_index_home_aliases(deepcopy_safe(parent_state))
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

    write_world_index_sidecar(index, parent_state, function(parent_saved)
        if not parent_saved then
            cb(false)
            return
        end
        set_world_index_state(index, parent_state, parent_state.file_id)

        state.return_pending = nil
        state.parent_world_index_state = nil
        write_world_index_sidecar(index, state, function(adventure_saved)
            cb(adventure_saved == true)
        end, state.file_id)
    end, parent_state.file_id)
end

local function resume_suspended_world_index(index, parent_state, cb)
    cb = cb or noop
    parent_state = ensure_world_index_home_aliases(deepcopy_safe(parent_state))
    if parent_state == nil or not switch_index_to_current_world(index, parent_state) then
        cb(false)
        return
    end

    parent_state.active = true
    parent_state.suspend_reason = nil
    parent_state.suspended_at = nil
    parent_state.updated_at = os.time()
    local home = get_world_index_home_state(parent_state)
    local worldgenoverride = parent_state.current_worldgenoverride or (home ~= nil and home.worldgenoverride or nil)
    restore_worldgenoverride(index, worldgenoverride, function(worldgenoverride_saved)
        if not worldgenoverride_saved then
            cb(false)
            return
        end
        save_index(index, function(index_saved)
            if not index_saved then
                cb(false)
                return
            end
            write_world_index_sidecar(index, parent_state, function(sidecar_saved)
                if sidecar_saved then
                    set_world_index_state(index, parent_state, parent_state.file_id)
                end
                cb(sidecar_saved == true)
            end, parent_state.file_id)
        end)
    end)
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
        (get_world_index_home_state(recovery) ~= nil and get_world_index_home_state(recovery).worldgenoverride or nil)

    restore_worldgenoverride(index, worldgenoverride, function(worldgenoverride_saved)
        if not worldgenoverride_saved then
            cb(false)
            return
        end
        save_index(index, function(index_saved)
            if not index_saved then
                cb(false)
                return
            end
            write_world_index_sidecar(index, recovery, function(sidecar_saved)
                if not sidecar_saved then
                    cb(false)
                    return
                end
                set_world_index_state(index, recovery)
                cb(true)
            end)
        end)
    end)
end

local function normalize_world_index_target(target)
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

local function normalize_world_index_existing_target(index, target)
    target = normalize_world_index_target(target)
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
        player_positions = deepcopy_safe(target.player_positions) or get_player_positions(target.player_sessions),
        cleanup_on_return = target.cleanup_on_return == true,
        world_type = normalize_world_type(target.world_type or target.location or target.dlc or target.mode),
        current_preset = get_worldgen_preset_id(target.current_preset or target.preset),
        id = target.id,
    }
end

local function get_world_index_generated_level(target, shardid)
    target = normalize_world_index_target(target)
    if target == nil or target.type == "existing" then
        return nil
    end
    return get_level_for_shard(target.level or target.current_preset or target, shardid)
end

local function get_world_index_target_for_shard(target, shardid)
    target = normalize_world_index_target(target)
    if target == nil or target.type == "existing" or is_master_shard_id(shardid) then
        return target
    end

    local level = get_world_index_generated_level(target, shardid)
    if level == nil then
        return target
    end

    target.level = level
    target.world_type = resolve_level_world_type(level)
    return target
end

local function get_world_index_preset_id(preset)
    if type(preset) == "table" then
        return preset.id or preset.worldgen_preset or preset.preset or preset.settings_preset or preset.world_type
    end
    return preset
end

local function get_world_index_target_id(target)
    target = normalize_world_index_target(target)
    if target == nil then
        return nil
    end
    if target.type == "existing" then
        return target.id or target.session_id
    end
    return get_world_index_preset_id(target.level) or
        get_world_index_preset_id(target.current_preset) or
        target.world_type
end

local function get_current_world_type(index)
    local runtime_world_type = get_runtime_world_type()
    if runtime_world_type ~= nil then
        return runtime_world_type
    end

    local session_id = index ~= nil and index:GetSession() or nil
    local state = get_world_index_state(index)
    if state ~= nil and state.current_session_id == session_id then
        local current_target = normalize_world_index_target(state.current_target)
        local world_type = normalize_world_type(state.world_type)
        if world_type == nil and current_target ~= nil then
            world_type = resolve_level_world_type(get_world_index_generated_level(current_target, get_index_shard(index))) or
                current_target.world_type
        end
        if world_type ~= nil then
            return world_type
        end
    end

    return get_stored_world_type({ world = index.world })
end

local function is_current_world_target(index, target)
    target = normalize_world_index_target(target)
    if index == nil or target == nil then
        return false
    end

    if target.type == "existing" then
        return target.session_id ~= nil and target.session_id == index:GetSession()
    end

    local target_world_type = resolve_level_world_type(get_world_index_generated_level(target, get_index_shard(index))) or
        target.world_type
    return target_world_type ~= nil and target_world_type == get_current_world_type(index)
end

local function reject_current_world_target(index, target, kind)
    if kind ~= "adventure" and is_current_world_target(index, target) then
        print("[Shard World Index] Already in target world "..tostring(get_world_index_target_id(target)).."; switch refused.")
        return true
    end
    return false
end

local function reject_unavailable_world_target(index, target, kind)
    target = normalize_world_index_target(target)
    if kind == "adventure" or target == nil or target.type == "existing" then
        return false
    end

    local shardid = get_index_shard(index)
    local level = get_world_index_generated_level(target, shardid)
    local world_type = resolve_level_world_type(level)
    local file_id = get_world_index_file_id_for_shard(world_type, shardid)
    if not is_known_world_index_file_id(file_id, shardid) then
        print("[Shard World Index] World type "..tostring(world_type).." is not available on shard "..tostring(shardid)..".")
        return true
    end
    return false
end

local function should_regenerate_current_world_index_session(index, state)
    ensure_world_index_home_aliases(state)

    local home = get_world_index_home_state(state)
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

local function get_current_world_index_regen_target(state)
    local generated_target = normalize_world_index_target(state.generated_target)
    if generated_target ~= nil and generated_target.type == "generated" then
        return generated_target
    end
    return normalize_world_index_target(state.current_target or state.current_preset)
end

local function get_current_world_index_regen_worldgenoverride(index, state)
    if state.current_worldgenoverride ~= nil then
        return state.current_worldgenoverride
    end

    local target = get_current_world_index_regen_target(state)
    local level = get_world_index_generated_level(target, get_index_shard(index))
    return level ~= nil and build_level_worldgenoverride_raw(level) or nil
end

local function prepare_current_world_index_regen(index, state, cb)
    cb = cb or noop
    if not should_regenerate_current_world_index_session(index, state) then
        return false
    end

    local player_sessions = state.secondary ~= true and collect_player_sessions() or nil
    if player_sessions ~= nil then
        state.player_sessions = player_sessions
        if state.kind == "adventure" then
            state.adventure_player_sessions = merge_session_lists(player_sessions, state.adventure_player_sessions)
        end
    end

    local target = get_current_world_index_regen_target(state)
    if target ~= nil and target.type == "generated" then
        state.current_target = target
        state.current_preset = get_world_index_target_id(target) or state.current_preset
    end

    state.current_session_id = nil
    state.cleanup_session_id = nil
    state.pending_generation = nil
    state.checked_existing_world = nil
    state.generation_source_session_id = nil
    state.generation_recovery_state = nil
    state.last_player_session_injected = nil
    state.updated_at = os.time()
    set_world_index_state(index, state)

    local worldgenoverride = get_current_world_index_regen_worldgenoverride(index, state)
    if worldgenoverride ~= nil then
        state.current_worldgenoverride = worldgenoverride
        restore_worldgenoverride(index, worldgenoverride, function(worldgenoverride_saved)
            if not worldgenoverride_saved then
                cb(false)
                return
            end
            write_world_index_sidecar(index, state, cb)
        end)
    else
        write_world_index_sidecar(index, state, cb)
    end
    return true
end

local function get_world_index_target_file_id(target, fallback, shardid)
    target = normalize_world_index_target(target)
    local file_id = fallback
    if target ~= nil then
        if target.file_id ~= nil then
            file_id = target.file_id
        elseif target.world_type ~= nil then
            file_id = target.world_type
        elseif target.type == "existing" then
            file_id = target.id or fallback
        else
            local level = target.level or target.current_preset
            if type(level) == "table" then
                file_id = normalize_world_type(level.world_type or level.location or level.dlc or level.mode)
            end
            file_id = file_id or get_world_index_target_id(target) or fallback
        end
    end

    return get_world_index_file_id_for_shard(file_id, shardid)
end

local function get_world_index_target_from_opts(opts, state)
    opts = opts or {}
    return normalize_world_index_target(opts.target or opts.world or opts.level or opts.current_preset or state and state.current_target)
end

local function apply_pending_world_generation_state(state)
    local pending = type(state.pending_generation) == "table" and state.pending_generation or nil
    if pending == nil then
        return
    end

    state.reason = pending.reason or state.reason
    state.chapter = pending.chapter or state.chapter
    state.current_target = normalize_world_index_target(pending.target or pending.current_target or pending.current_preset or pending.level) or state.current_target
    state.current_preset = get_world_index_preset_id(pending.current_preset) or
        get_world_index_preset_id(pending.level) or
        get_world_index_target_id(state.current_target) or
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
        state.file_id = normalize_world_index_file_id(pending.file_id)
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

local function should_cleanup_world_index_session(state)
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
    local home = get_world_index_home_state(state)
    return is_pending_world_generation_state(state) and
        session_identifier ~= nil and
        session_identifier ~= "" and
        home ~= nil and
        session_identifier ~= home.session_id and
        session_identifier ~= state.current_session_id
end

local function finish_generated_world_index(index, state, session_identifier, savedata, use_existing_world, cb)
    cb = cb or noop

    if state == nil or not state.active then
        cb(true)
        return
    end

    local home = get_world_index_home_state(state)
    if home == nil or home.session_id == nil or home.session_id == "" then
        print("[Shard World Index] Clearing sidecar without a stashed home world.")
        clear_world_index_sidecar(index, cb)
        return
    end

    if session_identifier == nil or session_identifier == "" then
        cb(false)
        return
    end

    local actual_world_type = get_savedata_world_type(savedata)
    if actual_world_type ~= nil then
        local expected_world_type = resolve_level_world_type(
            get_world_index_generated_level(state.current_target, get_index_shard(index)))
        if expected_world_type ~= nil and actual_world_type ~= expected_world_type then
            print("[Shard World Index] Generated session world type mismatch: expected "..
                tostring(expected_world_type)..", got "..tostring(actual_world_type)..".")
        end
        state.world_type = actual_world_type
    end

    if type(state.generation_source_session_id) == "string" and state.generation_source_session_id ~= "" then
        for _, session in ipairs(state.player_sessions or {}) do
            session.origin_session_id = session.origin_session_id or state.generation_source_session_id
        end
    end

    state.current_session_id = session_identifier
    state.updated_at = os.time()
    state.current_world = deepcopy_safe(index.world)
    state.current_server = deepcopy_safe(index.server)
    state.current_enabled_mods = deepcopy_safe(index.enabled_mods)
    state.generation_source_session_id = nil
    state.generation_recovery_state = nil
    set_world_index_state(index, state)

    local can_process_sessions = TheNet ~= nil and TheNet:GetIsServer()
    local should_inject_players = can_process_sessions and
        has_pending_player_sessions(state) and
        state.last_player_session_injected ~= session_identifier
    local cleanup_session_id = state.cleanup_session_id

    local function save_state()
        local has_cleanup_session = cleanup_session_id ~= nil and cleanup_session_id ~= ""
        local should_cleanup_session = can_process_sessions and
            should_cleanup_world_index_session(state) and
            has_cleanup_session and
            cleanup_session_id ~= home.session_id

        if not has_cleanup_session or cleanup_session_id == home.session_id then
            state.cleanup_session_id = nil
            write_world_index_sidecar(index, state, cb)
            return
        end

        if not should_cleanup_session then
            state.cleanup_session_id = nil
            write_world_index_sidecar(index, state, cb)
            return
        end

        state.cleanup_session_id = nil
        write_world_index_sidecar(index, state, function(sidecar_saved)
            if not sidecar_saved then
                state.cleanup_session_id = cleanup_session_id
                cb(false)
                return
            end
            state.cleanup_session_id = nil
            delete_session_if_not_home(cleanup_session_id, home.session_id)
            cb(true)
        end)
    end

    if should_inject_players then
        local function on_players_injected()
            state.player_sessions = nil
            state.last_player_session_injected = session_identifier
            save_state()
        end

        if use_existing_world then
            inject_player_sessions_into_existing_world(index, session_identifier, state.player_sessions, on_players_injected, nil, state.player_positions)
        else
            inject_player_sessions_into_world(index, state.player_sessions, session_identifier, savedata, on_players_injected)
        end
        return
    end

    save_state()
end

local function build_world_index_client_state(state)
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
        current_preset = get_world_index_preset_id(state.current_preset),
        current_session_id = state.current_session_id,
        current_target = get_world_index_target_id(state.current_target),
        total_chapters = total_chapters,
        started_at = state.started_at,
        updated_at = state.updated_at,
        finished_at = state.finished_at,
        return_reason = state.return_reason,
    }
end

local function write_world_index_topology_state(savedata, state)
    if savedata == nil or savedata.map == nil or savedata.map.topology == nil then
        return
    end

    local client_state = build_world_index_client_state(state)
    savedata.map.topology.world_index_state = client_state
end

local function commit_world_index_existing_target(index, state, target, cb)
    cb = cb or noop
    target = normalize_world_index_existing_target(index, target)
    if target == nil then
        print("[Shard World Index] Missing existing target session.")
        cb(false)
        return
    end

    local cleanup_session_id = state.cleanup_session_id
    local target_file_id = state.file_id
    state.current_target = normalize_world_index_target(target)
    state.current_preset = target.current_preset or state.current_preset or target.id or target.session_id
    state.current_session_id = target.session_id
    if cleanup_session_id == target.session_id then
        state.cleanup_session_id = nil
    end
    state.cleanup_current_on_return = target.cleanup_on_return == true
    if not should_cleanup_world_index_session(state) then
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
    state.player_positions = deepcopy_safe(target.player_positions)
    state.file_id = target_file_id
    set_world_index_state(index, state)

    switch_index_to_existing_world(index, target)

    local function save_target()
        write_world_index_sidecar(index, state, function(sidecar_saved)
            if not sidecar_saved then
                cb(false)
                return
            end
            save_index(index, function(index_saved)
                if not index_saved then
                    cb(false)
                    return
                end
                local sessions = state.player_sessions
                if sessions ~= nil and #sessions > 0 and TheNet ~= nil and TheNet:GetIsServer() then
                    inject_player_sessions_into_existing_world(index, target.session_id, sessions, function()
                        state.player_sessions = nil
                        state.last_player_session_injected = target.session_id
                        local should_delete = should_cleanup_world_index_session(state) and
                            cleanup_session_id ~= nil and cleanup_session_id ~= "" and cleanup_session_id ~= target.session_id
                        if should_delete then
                            state.cleanup_session_id = nil
                        end
                        write_world_index_sidecar(index, state, function(final_sidecar_saved)
                            if not final_sidecar_saved then
                                if should_delete then
                                    state.cleanup_session_id = cleanup_session_id
                                end
                                cb(false)
                                return
                            end
                            if should_delete then
                                delete_session_if_not_home(cleanup_session_id, target.session_id)
                            end
                            cb(true)
                        end)
                    end, nil, target.player_positions)
                else
                    local should_delete = should_cleanup_world_index_session(state) and
                        cleanup_session_id ~= nil and cleanup_session_id ~= "" and cleanup_session_id ~= target.session_id
                    if should_delete then
                        state.cleanup_session_id = nil
                        write_world_index_sidecar(index, state, function(final_sidecar_saved)
                            if not final_sidecar_saved then
                                state.cleanup_session_id = cleanup_session_id
                                cb(false)
                                return
                            end
                            delete_session_if_not_home(cleanup_session_id, target.session_id)
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
        restore_worldgenoverride(index, target.worldgenoverride, function(success)
            if success then
                save_target()
            else
                cb(false)
            end
        end)
    else
        save_target()
    end
end

local function commit_world_index_generated_target(index, state, target, keep_session, cb)
    cb = cb or noop
    target = normalize_world_index_target(target)

    local level = get_world_index_generated_level(target, get_index_shard(index))
    if level == nil then
        print("[Shard World Index] Missing generated target level.")
        cb(false)
        return
    end

    local level_world_type = resolve_level_world_type(level)
    local target_preset = get_world_index_preset_id(level)

    local valid, reason = validate_world_index_generated_level(level)
    if not valid then
        print("[Shard World Index] Refusing to switch world: "..tostring(reason)..".")
        cb(false)
        return
    end

    local file_id = state.file_id
    if not state.checked_existing_world and target.reuse_existing ~= false and state.reuse_existing ~= false then
        state.checked_existing_world = true

        local function generate_target()
            commit_world_index_generated_target(index, state, target, keep_session, cb)
        end

        local function reuse_target(existing_target)
            state.checked_existing_world = nil
            state.generated = existing_target.generated == true or nil
            state.generated_target = normalize_world_index_target(target)
            state.cleanup_current_on_return = false
            commit_world_index_existing_target(index, state, existing_target, cb)
        end

        local function check_existing_sidecar()
            read_world_index_sidecar(index, function(existing_state)
                local session_id = existing_state ~= nil and existing_state.current_session_id or nil
                if session_id == nil or session_id == "" then
                    generate_target()
                    return
                end

                read_world_session_world_type(index, session_id, function(actual_world_type, exists)
                    local target_world_type = target.world_type or level_world_type
                    if exists and actual_world_type == target_world_type and
                        existing_state.current_preset == target_preset then
                        reuse_target({
                            type = "existing",
                            id = existing_state.current_preset or get_world_index_target_id(target),
                            current_preset = existing_state.current_preset,
                            session_id = session_id,
                            worldgenoverride = existing_state.current_worldgenoverride or build_level_worldgenoverride_raw(level),
                            world = existing_state.current_world or { options = resolve_level_options(level) },
                            server = existing_state.current_server,
                            enabled_mods = existing_state.current_enabled_mods,
                            world_type = actual_world_type,
                            player_positions = existing_state.player_positions,
                            generated = true,
                            cleanup_on_return = false,
                        })
                        return
                    end

                    if exists and actual_world_type ~= target_world_type then
                        print("[Shard World Index] Stored session "..tostring(session_id)..
                            " is "..tostring(actual_world_type)..", not "..tostring(target_world_type).."; refusing reuse.")
                    elseif exists then
                        print("[Shard World Index] Stored session "..tostring(session_id)..
                            " uses preset "..tostring(existing_state.current_preset)..", not "..
                            tostring(target_preset).."; refusing reuse.")
                    end
                    existing_state.current_session_id = nil
                    existing_state.active = false
                    existing_state.world_type = actual_world_type or existing_state.world_type
                    write_world_index_sidecar(index, existing_state, function(saved)
                        if saved then
                            generate_target()
                        else
                            cb(false)
                        end
                    end, file_id)
                end)
            end, file_id)
        end

        local home = get_world_index_home_state(state)
        local target_world_type = target.world_type or resolve_level_world_type(level)
        if home.session_id ~= nil and home.session_id ~= "" then
            read_world_session_world_type(index, home.session_id, function(actual_world_type, exists)
                if actual_world_type ~= nil then
                    home.world_type = actual_world_type
                end
                if exists and actual_world_type == target_world_type and
                    home.current_preset == target_preset then
                    print("[Shard World Index] Reusing stored home world for "..tostring(target_world_type)..".")
                    reuse_target({
                        type = "existing",
                        id = get_world_index_target_id(target),
                        current_preset = home.current_preset,
                        session_id = home.session_id,
                        worldgenoverride = home.worldgenoverride or build_level_worldgenoverride_raw(level),
                        world = home.world or { options = resolve_level_options(level) },
                        server = home.server,
                        enabled_mods = home.enabled_mods,
                        world_type = actual_world_type,
                        player_positions = home.player_positions,
                        cleanup_on_return = false,
                    })
                    return
                end

                if exists and actual_world_type ~= target_world_type then
                    print("[Shard World Index] Home session "..tostring(home.session_id)..
                        " is "..tostring(actual_world_type)..", not "..tostring(target_world_type).."; refusing reuse.")
                elseif exists then
                    print("[Shard World Index] Home session "..tostring(home.session_id)..
                        " uses preset "..tostring(home.current_preset)..", not "..
                        tostring(target_preset).."; refusing reuse.")
                end
                check_existing_sidecar()
            end)
        else
            check_existing_sidecar()
        end
        return
    end
    state.checked_existing_world = nil

    state.current_target = target
    state.current_preset = target_preset
    state.cleanup_current_on_return = target.cleanup_on_return == true
    state.updated_at = os.time()
    state.generation_source_session_id = state.generation_source_session_id or index:GetSession()
    state.generation_recovery_state = state.generation_recovery_state or
        build_generation_recovery_state(index, state, state.generation_source_session_id)
    state.current_session_id = nil
    state.player_positions = nil
    set_world_index_state(index, state)
    switch_index_to_generated_world(index, level, keep_session ~= false)

    local worldgenoverride = build_level_worldgenoverride_raw(level)
    write_worldgenoverride_str(index, worldgenoverride, function(worldgenoverride_saved)
        if not worldgenoverride_saved then
            cb(false)
            return
        end
        state.generated = true
        state.generated_target = normalize_world_index_target(target)
        state.world_type = level_world_type
        state.current_worldgenoverride = worldgenoverride
        state.current_world = deepcopy_safe(index.world)
        state.current_server = deepcopy_safe(index.server)
        state.current_enabled_mods = deepcopy_safe(index.enabled_mods)
        write_world_index_sidecar(index, state, function(sidecar_saved)
            if not sidecar_saved then
                cb(false)
                return
            end
            save_index(index, function(index_saved)
                cb(index_saved == true)
            end)
        end)
    end)
end

local function commit_world_index_target(index, state, target, keep_session, cb)
    target = normalize_world_index_target(target)
    if target == nil then
        print("[Shard World Index] Missing target world.")
        cb(false)
        return
    end
    local shardid = get_index_shard(index)
    state.file_id = get_world_index_file_id_for_shard(state.file_id or get_world_index_target_file_id(target, nil, shardid), shardid)

    if target.type == "existing" then
        commit_world_index_existing_target(index, state, target, cb)
    else
        commit_world_index_generated_target(index, state, target, keep_session, cb)
    end
end

local function load_world_index_sidecar_state(index, state, cb)
    cb = cb or noop
    ensure_world_index_home_aliases(state)

    if state == nil then
        set_world_index_state(index, state)
        cb(true)
        return
    end

    if not state.active then
        set_world_index_state(index, state)
        if type(state.return_pending) == "table" and type(state.parent_world_index_state) == "table" then
            print("[Shard World Index] Restoring parent world index after interrupted adventure return.")
            restore_parent_world_index(index, state, cb)
        else
            cb(true)
        end
        return
    end

    if world_index_state_has_origin(state) and not world_index_state_matches_index(index, state) then
        print("[Shard World Index] Clearing sidecar from another slot or shard.")
        clear_world_index_sidecar(index, cb)
        return
    end

    local session_id = index:GetSession()
    if is_world_index_transition_restart() then
        set_world_index_state(index, state)
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
                finish_generated_world_index(index, state, session_id, nil, true, cb)
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
            set_world_index_state(index, state)
            cb()
            return
        end

        if world_index_state_matches_index(index, state) then
            print("[Shard World Index] Restoring stored world after interrupted transition.")
            finish_interrupted_return_to_stored_world(index, state, cb)
        else
            print("[Shard World Index] Clearing interrupted transition before regenerating the slot.")
            prepare_interrupted_world_index_regen(index)
            clear_interrupted_world_index_transition(index, cb)
        end
        return
    end

    if type(state.pending_generation) == "table" then
        world_session_exists(index, session_id, function(exists)
            if exists then
                set_world_index_state(index, state)
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
                    finish_generated_world_index(index, state, session_id, nil, true, cb)
                else
                    set_world_index_state(index, state)
                    cb()
                end
            else
                print("[Shard World Index] Current generated session is missing; returning to stashed home world.")
                finish_interrupted_return_to_stored_world(index, state, cb)
            end
        end)
        return
    end

    local home = get_world_index_home_state(state)
    if home ~= nil and home.session_id == session_id then
        print("[Shard World Index] Finishing interrupted return to stored world.")
        finish_interrupted_return_to_stored_world(index, state, cb)
        return
    end

    print("[Shard World Index] Clearing stale sidecar for unrelated session.")
    clear_world_index_sidecar(index, cb)
end

local function read_named_world_index_sidecar_in_slot(slot, file_id, cb)
    cb = cb or noop
    if slot == nil or TheSim == nil then
        cb(nil, false)
        return
    end

    file_id = normalize_world_index_file_id(file_id)
    local filename = "shardindex_"..file_id
    TheSim:GetPersistentStringInClusterSlot(slot, "Master", filename, function(load_success, str)
        if load_success and str ~= nil and #str > 0 then
            local success, data = RunInSandboxSafe(str)
            if success and type(data) == "table" then
                data.file_id = normalize_world_index_file_id(data.file_id or file_id)
                cb(ensure_world_index_home_aliases(data), true)
                return
            end
            cb(nil, true)
            return
        end
        cb(nil, false)
    end)
end

local function read_world_index_sidecar_in_slot(slot, cb)
    cb = cb or noop
    local ids = get_known_world_index_file_ids(nil)
    local i = 1

    local function read_next()
        if i > #ids then
            cb(nil)
            return
        end

        local file_id = ids[i]
        i = i + 1
        read_named_world_index_sidecar_in_slot(slot, file_id, function(state)
            if world_index_state_reserves_slot(state) then
                cb(state)
                return
            end
            read_next()
        end)
    end

    read_next()
end

local function read_active_world_index_sidecar(slot, cb)
    cb = cb or noop
    read_world_index_sidecar_in_slot(slot, function(state)
        cb(world_index_state_reserves_slot(state) and state or nil)
    end)
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

function ShardWorldIndex:InjectPlayerSessionsIntoExistingWorld(index, session_id, sessions, cb, spawn_override, player_positions, spawn_prefab)
    index, session_id, sessions, cb, spawn_override, player_positions, spawn_prefab = resolve_index_args(self, index, session_id, sessions, cb, spawn_override, player_positions, spawn_prefab)
    inject_player_sessions_into_existing_world(index, session_id, sessions, cb, spawn_override, player_positions, spawn_prefab)
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

function ShardWorldIndex:RequestSecondaryWorldIndex(name, data, cb, timeout)
    return request_secondary_world_index(name, data, cb, timeout)
end

function ShardWorldIndex:CommitSecondaryWorldIndex(request, cb, timeout)
    return commit_secondary_world_index_request(request, cb, timeout)
end

function ShardWorldIndex:AbortSecondaryWorldIndex(request)
    abort_secondary_world_index_request(request)
end

function ShardWorldIndex:IsSecondaryWorldIndexRequestPending()
    return pending_secondary_world_index_request ~= nil or next(prepared_secondary_world_index_requests) ~= nil
end

function ShardWorldIndex:HandleSecondaryWorldIndexReply(shardid, data)
    return handle_secondary_world_index_reply(shardid, data)
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

function ShardWorldIndex:RollbackPendingGeneration(index, cb, file_id)
    index, cb, file_id = resolve_index_args(self, index, cb, file_id)
    cb = cb or noop

    local state = get_world_index_state(index, file_id)
    local session_id = index ~= nil and index:GetSession() or nil
    local pending = state ~= nil and type(state.pending_generation) == "table" and state.pending_generation or nil
    local source_session_id = state ~= nil and
        (state.generation_source_session_id or (pending ~= nil and pending.generation_source_session_id or nil)) or nil
    local recovery = state ~= nil and
        (state.generation_recovery_state or (pending ~= nil and pending.generation_recovery_state or nil)) or nil
    if state == nil or
        state.active ~= true or
        not is_pending_world_generation_state(state) then
        cb(false, false)
        return false
    end
    if session_id == nil or
        session_id == "" or
        source_session_id ~= session_id or
        type(recovery) ~= "table" or
        recovery.current_session_id ~= session_id then
        print("[Shard World Index] Refusing to roll back an unrelated pending world generation.")
        cb(false, true)
        return false
    end

    local rollback_state = deepcopy_safe(state)
    rollback_state.generation_source_session_id = source_session_id
    rollback_state.generation_recovery_state = deepcopy_safe(recovery)
    recover_interrupted_generation_source(index, rollback_state, function(success)
        cb(success, true)
    end)
    return true
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
    return get_world_index_state(index, file_id)
end

function ShardWorldIndex:SetState(index, state, file_id)
    index, state, file_id = resolve_index_args(self, index, state, file_id)
    set_world_index_state(index, state, file_id)
end

function ShardWorldIndex:IsActive(index)
    index = resolve_index_args(self, index)
    local state = get_world_index_state(index)
    return state ~= nil and state.active == true
end

function ShardWorldIndex:ReadSidecar(index, cb, file_id)
    index, cb, file_id = resolve_index_args(self, index, cb, file_id)
    read_world_index_sidecar(index, cb, file_id)
end

function ShardWorldIndex:WriteSidecar(index, state, cb, file_id)
    index, state, cb, file_id = resolve_index_args(self, index, state, cb, file_id)
    write_world_index_sidecar(index, state, cb, file_id)
end

function ShardWorldIndex:ClearSidecar(index, cb, file_id)
    index, cb, file_id = resolve_index_args(self, index, cb, file_id)
    clear_world_index_sidecar(index, cb, file_id)
end

function ShardWorldIndex:ClearAllSidecars(index, cb)
    index, cb = resolve_index_args(self, index, cb)
    clear_all_world_index_sidecars(index, cb)
end

function ShardWorldIndex:RestoreParentWorldIndex(index, state, cb)
    index, state, cb = resolve_index_args(self, index, state, cb)
    restore_parent_world_index(index, state, cb)
end

function ShardWorldIndex:LoadSidecar(index, cb, file_id)
    index, cb, file_id = resolve_index_args(self, index, cb, file_id)
    read_world_index_sidecar(index, function(state)
        load_world_index_sidecar_state(index, state, cb)
    end, file_id)
end

function ShardWorldIndex:NeedsGenerationOnLoad(index)
    index = resolve_index_args(self, index)
    return is_load_slot() and is_pending_world_generation_state(get_world_index_state(index))
end

function ShardWorldIndex:ReservesSlot(index)
    index = resolve_index_args(self, index)
    local state = get_world_index_state(index)
    return world_index_state_reserves_slot(state) and not is_load_slot()
end

function ShardWorldIndex:PreservePendingGenerationOnDelete(index, save_options, cb)
    index, save_options, cb = resolve_index_args(self, index, save_options, cb)
    local state = get_world_index_state(index)
    if save_options and
        state ~= nil and
        state.active and
        should_preserve_pending_world_generation(state) and
        not should_regenerate_current_world_index_session(index, state) then
        local staged_world = deepcopy_safe(index.world)
        local staged_server = deepcopy_safe(index.server)
        local staged_enabled_mods = deepcopy_safe(index.enabled_mods)
        local staged_session_id = index:GetSession()
        local home = get_world_index_home_state(state)
        if home ~= nil and home.session_id ~= nil and home.session_id ~= "" and
            (staged_session_id == nil or staged_session_id == "") then
            switch_index_to_existing_world(index, home)
        end

        index:MarkDirty()
        save_index(index, function(index_saved)
            index.world = staged_world or { options = {} }
            index.server = staged_server or {}
            index.enabled_mods = staged_enabled_mods or {}
            index.session_id = staged_session_id
            index:MarkDirty()
            set_world_index_state(index, state)
            if not index_saved then
                if cb ~= nil then
                    cb(false)
                end
                return
            end
            write_world_index_sidecar(index, state, cb)
        end)
        return true
    end

    return false
end

function ShardWorldIndex:PrepareDelete(index, save_options, cb)
    index, save_options, cb = resolve_index_args(self, index, save_options, cb)
    local state = get_world_index_state(index)
    if save_options and state ~= nil and state.active then
        if prepare_current_world_index_regen(index, state, cb) then
            return
        end
        prepare_interrupted_world_index_regen(index)
    end

    clear_all_world_index_sidecars(index, cb)
end

function ShardWorldIndex:PrepareSetServerShardData(index, cb)
    index, cb = resolve_index_args(self, index, cb)
    local state = get_world_index_state(index)
    -- Dedicated startup refreshes server data after loading an existing shard.
    if state ~= nil and
        state.active and
        not world_index_state_matches_current_session(index, state) and
        not should_preserve_pending_world_generation(state) then
        prepare_interrupted_world_index_regen(index)
        clear_interrupted_world_index_transition(index, cb)
        return true
    end

    return false
end

function ShardWorldIndex:BeforeGenerateNewWorld(index, savedata, metadataStr, session_identifier)
    index, savedata, metadataStr, session_identifier = resolve_index_args(self, index, savedata, metadataStr, session_identifier)
    local state = get_world_index_state(index)
    if state ~= nil and state.active then
        apply_pending_world_generation_state(state)
        local world_table = get_savedata_table(savedata)
        state.current_session_id = session_identifier
        state.updated_at = os.time()
        write_world_index_topology_state(world_table, state)
        if type(savedata) == "string" and type(world_table) == "table" then
            savedata = DataDumper(world_table, nil, BRANCH ~= "dev")
        end
    end
    return savedata, metadataStr
end

function ShardWorldIndex:AfterGenerateNewWorld(index, savedata, session_identifier, cb)
    index, savedata, session_identifier, cb = resolve_index_args(self, index, savedata, session_identifier, cb)
    cb = cb or noop

    local state = get_world_index_state(index)
    if state ~= nil and state.active then
        finish_generated_world_index(index, state, session_identifier, savedata, false, cb)
        return
    end

    cb()
end

function ShardWorldIndex:BeginWorldIndex(index, opts, cb)
    index, opts, cb = resolve_index_args(self, index, opts, cb)
    cb = cb or noop
    opts = opts or {}

    local active_state = get_world_index_state(index)
    if active_state ~= nil and active_state.active == true then
        if opts.kind == "adventure" and active_state.kind ~= "adventure" then
            print("[Shard World Index] Suspending normal world index before adventure.")
            suspend_current_world_index_for_adventure(index, active_state, function(parent_state, suspended)
                if not suspended then
                    cb(false)
                    return
                end
                opts = attach_parent_world_index_for_adventure(opts, parent_state)
                self:BeginWorldIndex(index, opts, function(success)
                    if success then
                        cb(true)
                    else
                        resume_suspended_world_index(index, parent_state, function()
                            cb(false)
                        end)
                    end
                end)
            end)
            return
        end

        print("[Shard World Index] A world index is already active.")
        cb(false)
        return
    end

    local home_session = index:GetSession()
    if home_session == nil or home_session == "" then
        print("[Shard World Index] Cannot switch without a current world session.")
        cb(false)
        return
    end

    local target = get_world_index_target_from_opts(opts)
    if target == nil then
        print("[Shard World Index] Missing target world.")
        cb(false)
        return
    end
    if reject_unavailable_world_target(index, target, opts.kind) or
        (opts.secondary ~= true and reject_current_world_target(index, target, opts.kind)) then
        cb(false)
        return
    end
    local shardid = get_index_shard(index)
    local file_id = get_world_index_file_id_for_shard(opts.file_id or get_world_index_target_file_id(target, nil, shardid), shardid)

    read_worldgenoverride_raw(index, function(home_wgo)
        local state = deepcopy_safe(opts.state) or {}
        state.active = true
        state.file_id = get_world_index_file_id_for_shard(state.file_id or file_id, shardid)
        state.kind = state.kind or opts.kind or "world_index"
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
        state.current_preset = state.current_preset or get_world_index_target_id(target)
        state.current_session_id = nil

        local is_secondary = state.secondary == true or opts.secondary == true
        local player_sessions = opts.player_sessions
        if player_sessions == nil and not is_secondary and opts.collect_player_sessions ~= false then
            player_sessions = collect_player_sessions()
        end
        opts.player_sessions = player_sessions
        if state.player_sessions == nil and opts.fallback_player_sessions ~= false then
            state.player_sessions = player_sessions
        end

        local home = state.home or state.main or build_world_index_home_state(index, home_wgo, opts)
        state.home = home
        state.main = state.main or deepcopy_safe(home)

        commit_world_index_target(index, state, target, opts.keep_session, cb)
    end)
end

function ShardWorldIndex:BeginSecondaryWorldIndex(index, opts, cb)
    index, opts, cb = resolve_index_args(self, index, opts, cb)
    opts = opts or {}
    opts.secondary = true
    opts.target = get_world_index_target_for_shard(get_world_index_target_from_opts(opts), get_index_shard(index))
    local state = deepcopy_safe(opts.state) or {}
    state.secondary = true
    opts.state = state
    self:BeginWorldIndex(index, opts, cb)
end

function ShardWorldIndex:AdvanceSecondaryWorldIndex(index, opts, cb)
    index, opts, cb = resolve_index_args(self, index, opts, cb)
    opts = opts or {}
    local state = get_world_index_state(index)
    if state == nil or not state.active then
        self:BeginSecondaryWorldIndex(index, opts, cb)
        return
    end
    opts.target = get_world_index_target_for_shard(get_world_index_target_from_opts(opts), get_index_shard(index))
    self:QueueNextWorld(index, opts, cb)
end

function ShardWorldIndex:QueueNextWorld(index, opts, cb)
    index, opts, cb = resolve_index_args(self, index, opts, cb)
    cb = cb or noop
    opts = opts or {}

    local state = get_world_index_state(index)
    if state == nil or not state.active or get_world_index_home_state(state) == nil then
        print("[Shard World Index] No active world index to advance.")
        cb(false)
        return
    end

    local target = get_world_index_target_from_opts(opts, state)
    if target == nil and opts.chapter ~= nil and type(state.level_sequence) == "table" then
        target = normalize_world_index_target(get_level_for_shard(state.level_sequence[opts.chapter], get_index_shard(index)))
    end
    if target == nil then
        print("[Shard World Index] Missing queued world.")
        cb(false)
        return
    end
    if reject_unavailable_world_target(index, target, state.kind) or
        (state.secondary ~= true and reject_current_world_target(index, target, state.kind)) then
        cb(false)
        return
    end
    local shardid = get_index_shard(index)
    local current_file_id = normalize_world_index_file_id(state.file_id)
    local queued_file_id = get_world_index_file_id_for_shard(opts.file_id or get_world_index_target_file_id(target, state.file_id, shardid), shardid)
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
    if state.kind ~= "adventure" then
        local player_positions = get_player_positions(player_sessions)
        set_player_positions_for_session(state, index:GetSession(), player_positions)
        if previous_state ~= nil then
            set_player_positions_for_session(previous_state, index:GetSession(), player_positions)
        end
    end
    pending.reason = pending.reason or opts.reason or "advance"
    pending.chapter = pending.chapter or opts.chapter
    pending.target = pending.target or target
    pending.current_target = pending.current_target or target
    pending.current_preset = pending.current_preset or get_world_index_target_id(target)
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
            write_world_index_sidecar(index, parked_state, function(parked_saved)
                if not parked_saved then
                    cb(false, pending_chapter)
                    return
                end
                set_world_index_state(index, parked_state, current_file_id)
                set_world_index_state(index, state, queued_file_id)
                cb(true, pending_chapter)
            end, current_file_id)
            return
        end

        if not success and previous_state ~= nil then
            write_world_index_sidecar(index, nil, function()
                set_world_index_state(index, nil, queued_file_id)
                set_world_index_state(index, previous_state, current_file_id)
                cb(false, pending_chapter)
            end, queued_file_id)
            return
        end

        cb(success, pending_chapter)
    end

    local function commit_queued_state()
        apply_pending_world_generation_state(state)
        commit_world_index_target(index, state, target, opts.keep_session, function(success)
            finish_commit(success)
        end)
    end

    if previous_state ~= nil then
        read_world_index_sidecar(index, function(existing_state)
            state.current_session_id = nil
            state.current_worldgenoverride = nil
            state.current_world = nil
            state.current_server = nil
            state.current_enabled_mods = nil
            state.generated = nil
            state.generated_target = nil
            state.player_positions = nil

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
                state.player_positions = deepcopy_safe(existing_state.player_positions)
            end

            write_world_index_sidecar(index, state, function(saved)
                if saved then
                    commit_queued_state()
                else
                    finish_commit(false)
                end
            end)
        end, queued_file_id)
        return
    end

    write_world_index_sidecar(index, state, function(saved)
        if saved then
            commit_queued_state()
        else
            finish_commit(false)
        end
    end)
end

function ShardWorldIndex:ReturnToStoredWorld(index, reason, cb, player_sessions, opts)
    index, reason, cb, player_sessions, opts = resolve_index_args(self, index, reason, cb, player_sessions, opts)
    cb = cb or noop
    opts = opts or {}

    local state = get_world_index_state(index)
    local home = get_world_index_home_state(state)
    if state == nil or not state.active or home == nil then
        print("[Shard World Index] No active world index to return from.")
        cb(false)
        return
    end

    local current_index =
    {
        session_id = index:GetSession(),
        world = deepcopy_safe(index.world),
        server = deepcopy_safe(index.server),
        enabled_mods = deepcopy_safe(index.enabled_mods),
    }
    local current_worldgenoverride = state.current_worldgenoverride
    local cleanup_session_id = should_cleanup_world_index_session(state) and state.current_session_id or nil
    local sessions = player_sessions or state.return_player_sessions

    local player_positions = get_player_positions(sessions)
    if player_positions ~= nil then
        set_player_positions_for_session(state, index:GetSession(), player_positions)
    end

    state.return_player_sessions = deepcopy_safe(sessions)
    state.return_pending =
    {
        reason = reason or "return",
        cleanup_session_id = cleanup_session_id,
        parent_world_index_file_id = type(state.parent_world_index_state) == "table" and
            state.parent_world_index_state.file_id or nil,
        started_at = os.time(),
    }
    state.updated_at = os.time()

    local function restore_current_index(done)
        index.session_id = current_index.session_id
        index.world = current_index.world or { options = {} }
        index.server = current_index.server or {}
        index.enabled_mods = current_index.enabled_mods or {}
        index:MarkDirty()
        restore_worldgenoverride(index, current_worldgenoverride, function()
            save_index(index, function()
                set_world_index_state(index, state)
                done(false)
            end)
        end)
    end

    local function commit_return()
        local finished_state = deepcopy_safe(state)
        finished_state.active = false
        finished_state.finished_at = os.time()
        finished_state.return_reason = reason or "return"
        finished_state.return_player_sessions = nil
        if opts.defer_cleanup and cleanup_session_id ~= nil and cleanup_session_id ~= "" then
            finished_state.deferred_cleanup_session_id = cleanup_session_id
        end
        if opts.defer_cleanup or opts.defer_parent_restore then
            finished_state.deferred_return = true
        end
        if type(finished_state.parent_world_index_state) ~= "table" then
            finished_state.return_pending = nil
        end

        switch_index_to_existing_world(index, home)
        restore_worldgenoverride(index, home.worldgenoverride, function(worldgenoverride_saved)
            if not worldgenoverride_saved then
                restore_current_index(cb)
                return
            end
            save_index(index, function(index_saved)
                if not index_saved then
                    restore_current_index(cb)
                    return
                end
                write_world_index_sidecar(index, finished_state, function(sidecar_saved)
                    if not sidecar_saved then
                        restore_current_index(cb)
                        return
                    end
                    set_world_index_state(index, finished_state)
                    if not opts.defer_cleanup and cleanup_session_id ~= nil and cleanup_session_id ~= "" then
                        delete_session_if_not_home(cleanup_session_id, home.session_id)
                    end
                    cb(true)
                end)
            end)
        end)
    end

    write_world_index_sidecar(index, state, function(pending_saved)
        if not pending_saved then
            state.return_pending = nil
            cb(false)
            return
        end

        if sessions ~= nil and #sessions > 0 and TheNet ~= nil and TheNet:GetIsServer() then
            local return_player_positions = home.player_positions
            if opts.ignore_saved_positions then
                return_player_positions = nil
            end
            inject_player_sessions_into_existing_world(index, home.session_id, sessions, function()
                state.return_player_sessions = nil
                state.last_player_session_injected = home.session_id
                commit_return()
            end, home.return_position, return_player_positions, opts.spawn_prefab)
            return
        end

        commit_return()
    end)
end

local function finalize_deferred_return(index, state, cb)
    cb = cb or noop
    if state == nil or state.active or state.deferred_return ~= true then
        cb(false)
        return
    end

    local cleanup_session_id = state.deferred_cleanup_session_id
    local function finish()
        state.deferred_return = nil
        state.deferred_cleanup_session_id = nil
        write_world_index_sidecar(index, state, function(saved)
            if not saved then
                state.deferred_return = true
                state.deferred_cleanup_session_id = cleanup_session_id
                cb(false)
                return
            end
            set_world_index_state(index, state, state.file_id)
            local home = get_world_index_home_state(state)
            if cleanup_session_id ~= nil and cleanup_session_id ~= "" and home ~= nil then
                delete_session_if_not_home(cleanup_session_id, home.session_id)
            end
            cb(true)
        end, state.file_id)
    end

    if type(state.parent_world_index_state) == "table" then
        restore_parent_world_index(index, state, function(parent_restored)
            if parent_restored then
                finish()
            else
                cb(false)
            end
        end)
    else
        finish()
    end
end

local function rollback_deferred_return(index, state, cb)
    cb = cb or noop
    if state == nil or state.active or state.deferred_return ~= true or not switch_index_to_current_world(index, state) then
        cb(false)
        return
    end

    state.active = true
    state.finished_at = nil
    state.return_reason = nil
    state.return_pending = nil
    state.deferred_return = nil
    state.deferred_cleanup_session_id = nil
    state.updated_at = os.time()
    restore_worldgenoverride(index, state.current_worldgenoverride, function(worldgenoverride_saved)
        if not worldgenoverride_saved then
            cb(false)
            return
        end
        save_index(index, function(index_saved)
            if not index_saved then
                cb(false)
                return
            end
            write_world_index_sidecar(index, state, function(sidecar_saved)
                if sidecar_saved then
                    set_world_index_state(index, state, state.file_id)
                end
                cb(sidecar_saved == true)
            end, state.file_id)
        end)
    end)
end

function ShardWorldIndex:FinalizeDeferredReturn(index, state, cb)
    index, state, cb = resolve_index_args(self, index, state, cb)
    finalize_deferred_return(index, state, cb)
end

function ShardWorldIndex:RollbackDeferredReturn(index, state, cb)
    index, state, cb = resolve_index_args(self, index, state, cb)
    rollback_deferred_return(index, state, cb)
end

local function get_secondary_transition_target(index, operation, opts, active_state)
    local target = nil
    local file_id = nil

    if operation == "BeginSecondaryAdventure" then
        local chapter = math.floor(tonumber(opts.chapter) or 1)
        local level = type(opts.level_sequence) == "table" and opts.level_sequence[chapter] or nil
        target = normalize_world_index_target({
            type = "generated",
            level = get_level_for_shard(level, get_index_shard(index)),
            world_type = "adventure",
            cleanup_on_return = true,
        })
        file_id = ADVENTURE_WORLD_INDEX_FILE_ID
    elseif operation == "AdvanceSecondaryAdventure" then
        local adventure_state = get_world_index_state(index, ADVENTURE_WORLD_INDEX_FILE_ID)
        local chapter = math.floor(tonumber(opts.chapter) or ((adventure_state ~= nil and adventure_state.chapter or 0) + 1))
        local level = adventure_state ~= nil and type(adventure_state.level_sequence) == "table" and
            adventure_state.level_sequence[chapter] or nil
        target = normalize_world_index_target({
            type = "generated",
            level = get_level_for_shard(level, get_index_shard(index)),
            world_type = "adventure",
            cleanup_on_return = true,
        })
        file_id = ADVENTURE_WORLD_INDEX_FILE_ID
    elseif operation == "ReturnSecondaryAdventure" then
        file_id = ADVENTURE_WORLD_INDEX_FILE_ID
    elseif operation == "BeginSecondaryWorldIndex" or operation == "AdvanceSecondaryWorldIndex" then
        target = get_world_index_target_for_shard(get_world_index_target_from_opts(opts, active_state), get_index_shard(index))
        file_id = get_world_index_target_file_id(target, active_state ~= nil and active_state.file_id or opts.file_id,
            get_index_shard(index))
    elseif operation == "ReturnSecondaryWorldIndex" then
        file_id = active_state ~= nil and active_state.file_id or opts.file_id
    end

    return target, normalize_world_index_file_id(file_id)
end

local function validate_secondary_transition(index, operation, opts, active_state, target)
    local is_begin = operation == "BeginSecondaryWorldIndex" or operation == "BeginSecondaryAdventure"
    local is_adventure_begin = operation == "BeginSecondaryAdventure"
    if is_begin then
        if index:GetSession() == nil or index:GetSession() == "" then
            return false, "missing home session"
        end
        if active_state ~= nil and active_state.active and not (is_adventure_begin and active_state.kind ~= "adventure") then
            return false, "world index already active"
        end
    elseif active_state == nil or not active_state.active then
        return false, "world index is not active"
    end

    local needs_target = operation ~= "ReturnSecondaryWorldIndex" and operation ~= "ReturnSecondaryAdventure"
    if needs_target and target == nil then
        return false, "missing target world"
    end
    if target ~= nil and target.type == "generated" then
        local level = get_world_index_generated_level(target, get_index_shard(index))
        local valid, reason = validate_world_index_generated_level(level)
        if not valid then
            return false, reason
        end
    elseif target ~= nil and target.type == "existing" and normalize_world_index_existing_target(index, target) == nil then
        return false, "missing existing target session"
    end

    return true
end

local function prepare_secondary_transition(index, operation, opts, cb)
    cb = cb or noop
    opts = deepcopy_safe(opts) or {}
    local request_id = opts.request_id
    if type(request_id) ~= "string" or request_id == "" then
        cb(false)
        return
    end

    local active_state = get_world_index_state(index)
    local target, file_id = get_secondary_transition_target(index, operation, opts, active_state)
    local valid, reason = validate_secondary_transition(index, operation, opts, active_state, target)
    if not valid then
        print("[Shard World Index] Cannot prepare "..tostring(operation)..": "..tostring(reason)..".")
        cb(false)
        return
    end

    read_named_world_index_sidecar(index, file_id, function(target_state)
        local existing = target_state ~= nil and target_state.secondary_transition or nil
        if type(existing) == "table" then
            cb(existing.request_id == request_id and existing.operation == operation, file_id)
            return
        end

        read_worldgenoverride_raw(index, function(worldgenoverride)
            local transaction =
            {
                request_id = request_id,
                operation = operation,
                status = "prepared",
                file_id = file_id,
                opts = opts,
                original_state = deepcopy_safe(active_state),
                original_state_file_id = active_state ~= nil and active_state.file_id or nil,
                original_target_state = deepcopy_safe(target_state),
                original_index =
                {
                    session_id = index:GetSession(),
                    world = deepcopy_safe(index.world),
                    server = deepcopy_safe(index.server),
                    enabled_mods = deepcopy_safe(index.enabled_mods),
                },
                original_worldgenoverride = worldgenoverride,
                prepared_at = os.time(),
            }
            local marker = deepcopy_safe(target_state) or
            {
                active = false,
                kind = opts.kind or (operation:find("Adventure") ~= nil and "adventure" or "world_index"),
                file_id = file_id,
                secondary = true,
                slot = index:GetSlot(),
                shard = get_index_shard(index),
            }
            marker.secondary_transition = transaction
            marker.updated_at = os.time()
            write_world_index_sidecar(index, marker, function(saved)
                if saved then
                    set_world_index_state(index, marker, file_id)
                end
                cb(saved == true, file_id)
            end, file_id)
        end)
    end)
end

local function find_secondary_transition(index, request_id, file_id, cb)
    cb = cb or noop
    local function check_state(state)
        local transaction = state ~= nil and state.secondary_transition or nil
        if type(transaction) == "table" and transaction.request_id == request_id then
            cb(state, transaction)
        else
            cb(nil, nil)
        end
    end

    if file_id ~= nil then
        local state = get_world_index_state(index, file_id)
        if state ~= nil and type(state.secondary_transition) == "table" and
            state.secondary_transition.request_id == request_id then
            check_state(state)
        else
            read_named_world_index_sidecar(index, file_id, check_state)
        end
        return
    end

    local ids = get_known_world_index_file_ids(index)
    local i = 1
    local function read_next()
        if i > #ids then
            cb(nil, nil)
            return
        end
        local current_file_id = ids[i]
        i = i + 1
        read_named_world_index_sidecar(index, current_file_id, function(state)
            local transaction = state ~= nil and state.secondary_transition or nil
            if type(transaction) == "table" and transaction.request_id == request_id then
                cb(state, transaction)
            else
                read_next()
            end
        end)
    end
    read_next()
end

local function restore_secondary_transition(index, state, transaction, cb)
    cb = cb or noop
    if transaction == nil then
        cb(true)
        return
    end

    local original_index = transaction.original_index or {}
    index.session_id = original_index.session_id
    index.world = deepcopy_safe(original_index.world) or { options = {} }
    index.server = deepcopy_safe(original_index.server) or {}
    index.enabled_mods = deepcopy_safe(original_index.enabled_mods) or {}
    index:MarkDirty()

    local function restore_original_sidecars()
        write_world_index_sidecar(index, transaction.original_target_state, function(target_restored)
            if not target_restored then
                cb(false)
                return
            end
            set_world_index_state(index, transaction.original_target_state, transaction.file_id)

            local original_file_id = transaction.original_state_file_id
            if original_file_id == nil or normalize_world_index_file_id(original_file_id) == transaction.file_id then
                cb(true)
                return
            end
            write_world_index_sidecar(index, transaction.original_state, function(state_restored)
                if state_restored then
                    set_world_index_state(index, transaction.original_state, original_file_id)
                end
                cb(state_restored == true)
            end, original_file_id)
        end, transaction.file_id)
    end

    restore_worldgenoverride(index, transaction.original_worldgenoverride, function(worldgenoverride_restored)
        if not worldgenoverride_restored then
            cb(false)
            return
        end
        save_index(index, function(index_restored)
            if not index_restored then
                cb(false)
                return
            end
            restore_original_sidecars()
        end)
    end)
end

local function dispatch_secondary_transition(index, operation, opts, transaction, cb)
    opts.secondary_transition = deepcopy_safe(transaction)
    if operation == "BeginSecondaryAdventure" then
        index.adventure:BeginSecondary(opts, cb)
    elseif operation == "AdvanceSecondaryAdventure" then
        index.adventure:AdvanceSecondary(opts, cb)
    elseif operation == "ReturnSecondaryAdventure" then
        index.adventure:ReturnToMainWorld(opts.reason or "return", cb,
            { defer_cleanup = true, defer_parent_restore = true })
    elseif operation == "BeginSecondaryWorldIndex" then
        opts.state = deepcopy_safe(opts.state) or {}
        opts.state.secondary_transition = deepcopy_safe(transaction)
        index.worldindex:BeginSecondaryWorldIndex(opts, cb)
    elseif operation == "AdvanceSecondaryWorldIndex" then
        index.worldindex:AdvanceSecondaryWorldIndex(opts, cb)
    elseif operation == "ReturnSecondaryWorldIndex" then
        index.worldindex:ReturnToStoredWorld(opts.reason or "return", cb, nil, { defer_cleanup = true })
    else
        cb(false)
    end
end

local function commit_prepared_secondary_transition(index, request_id, file_id, cb)
    cb = cb or noop
    find_secondary_transition(index, request_id, file_id, function(marker, transaction)
        if transaction == nil then
            cb(false)
            return
        end
        if transaction.status == "committed" then
            cb(true, transaction.file_id)
            return
        end

        transaction.status = "committing"
        marker.secondary_transition = transaction
        write_world_index_sidecar(index, marker, function(marked)
            if not marked then
                cb(false)
                return
            end
            dispatch_secondary_transition(index, transaction.operation, deepcopy_safe(transaction.opts) or {}, transaction, function(success)
                if not success then
                    restore_secondary_transition(index, marker, transaction, function()
                        cb(false)
                    end)
                    return
                end

                local result_state = get_world_index_state(index, transaction.file_id)
                if result_state == nil then
                    restore_secondary_transition(index, marker, transaction, function()
                        cb(false)
                    end)
                    return
                end
                transaction.status = "committed"
                transaction.committed_at = os.time()
                result_state.secondary_transition = transaction
                write_world_index_sidecar(index, result_state, function(saved)
                    if not saved then
                        restore_secondary_transition(index, result_state, transaction, function()
                            cb(false)
                        end)
                        return
                    end
                    set_world_index_state(index, result_state, transaction.file_id)
                    cb(true, transaction.file_id)
                end, transaction.file_id)
            end)
        end, transaction.file_id)
    end)
end

local function abort_prepared_secondary_transition(index, request_id, file_id, cb)
    cb = cb or noop
    find_secondary_transition(index, request_id, file_id, function(state, transaction)
        if transaction == nil then
            cb(true)
            return
        end
        restore_secondary_transition(index, state, transaction, cb)
    end)
end

local function finalize_secondary_transition(index, request_id, file_id, cb)
    cb = cb or noop
    find_secondary_transition(index, request_id, file_id, function(state, transaction)
        if transaction == nil then
            cb(true, false)
            return
        end
        if transaction.status ~= "committed" then
            cb(false, false)
            return
        end

        local cleanup_session_id = state.deferred_cleanup_session_id
        local deferred_return = state.deferred_return
        local function finish_finalize()
            state.deferred_return = nil
            state.deferred_cleanup_session_id = nil
            state.secondary_transition = nil
            write_world_index_sidecar(index, state, function(saved)
                if not saved then
                    state.deferred_return = deferred_return
                    state.deferred_cleanup_session_id = cleanup_session_id
                    state.secondary_transition = transaction
                    cb(false, true)
                    return
                end
                set_world_index_state(index, state, transaction.file_id)
                local home = get_world_index_home_state(state)
                if cleanup_session_id ~= nil and cleanup_session_id ~= "" and home ~= nil then
                    delete_session_if_not_home(cleanup_session_id, home.session_id)
                end
                cb(true, true)
            end, transaction.file_id)
        end

        if not state.active and type(state.parent_world_index_state) == "table" then
            restore_parent_world_index(index, state, function(parent_restored)
                if parent_restored then
                    finish_finalize()
                else
                    cb(false, true)
                end
            end)
        else
            finish_finalize()
        end
    end)
end

function ShardWorldIndex:PrepareSecondaryTransition(index, operation, opts, cb)
    index, operation, opts, cb = resolve_index_args(self, index, operation, opts, cb)
    prepare_secondary_transition(index, operation, opts, cb)
end

function ShardWorldIndex:CommitPreparedSecondaryTransition(index, request_id, file_id, cb)
    index, request_id, file_id, cb = resolve_index_args(self, index, request_id, file_id, cb)
    commit_prepared_secondary_transition(index, request_id, file_id, cb)
end

function ShardWorldIndex:AbortPreparedSecondaryTransition(index, request_id, file_id, cb)
    index, request_id, file_id, cb = resolve_index_args(self, index, request_id, file_id, cb)
    abort_prepared_secondary_transition(index, request_id, file_id, cb)
end

function ShardWorldIndex:FinalizeSecondaryTransition(index, request_id, file_id, cb)
    index, request_id, file_id, cb = resolve_index_args(self, index, request_id, file_id, cb)
    finalize_secondary_transition(index, request_id, file_id, cb)
end

function ShardWorldIndex:StartWorldIndex(index, opts, cb)
    index, opts, cb = resolve_index_args(self, index, opts, cb)
    cb = cb or noop
    if index == nil then
        cb(false)
        return false
    end
    if TheShard ~= nil and not is_master_shard() then
        print("[Shard World Index] StartWorldIndex must be called on the master shard.")
        cb(false)
        return false
    end

    opts = opts or {}

    local target = get_world_index_target_from_opts(opts)
    if target ~= nil and
        (reject_unavailable_world_target(index, target, opts.kind) or
        reject_current_world_target(index, target, opts.kind)) then
        cb(false)
        return false
    end

    local function begin_after_save()
        if opts.kind ~= "adventure" and opts.player_sessions == nil and opts.collect_player_sessions ~= false then
            opts.player_sessions = collect_player_sessions()
        end
        request_secondary_world_index("BeginSecondaryWorldIndex", {
            kind = opts.kind,
            reason = opts.reason,
            target = opts.target or opts.world or opts.level or opts.current_preset,
            file_id = opts.file_id,
            reuse_existing = opts.reuse_existing,
            keep_session = opts.keep_session,
            collect_player_sessions = false,
            fallback_player_sessions = false,
        }, function(secondary_ready, request)
            if not secondary_ready then
                print("[Shard World Index] Secondary shards did not prepare the target; Master will not change worlds.")
                cb(false)
                return
            end

            self:BeginWorldIndex(index, opts, function(success)
                if not success then
                    abort_secondary_world_index_request(request)
                    cb(false)
                    return
                end
                commit_secondary_world_index_request(request, function(committed)
                    if committed then
                        restart_current_slot_after_shard_rpc(index,
                        {
                            world_index_transition = opts.reason or "begin",
                            world_index_file_id = get_world_index_state(index) ~= nil and get_world_index_state(index).file_id or opts.file_id,
                        })
                    end
                    cb(committed == true)
                end, opts.secondary_shard_wait_timeout or nil)
            end)
        end)
    end

    if TheWorld ~= nil and TheWorld.ismastersim then
        if opts.force_players_to_master_modname ~= nil then
            send_force_players_to_master_rpc(opts.force_players_to_master_modname, opts.force_players_to_master_rpcname)
        end
        wait_for_secondary_shard_players_empty(function(players_ready)
            if not players_ready then
                cb(false)
                return
            end
            index:SaveCurrent(begin_after_save)
        end, opts.secondary_shard_wait_timeout or nil, opts.secondary_shard_wait_poll_interval or nil)
    else
        save_players()
        begin_after_save()
    end
    return true
end

function ShardWorldIndex:AdvanceWorldIndex(index, opts, cb)
    index, opts, cb = resolve_index_args(self, index, opts, cb)
    cb = cb or noop
    if index == nil or not self:IsActive(index) then
        cb(false)
        return false
    end
    if TheShard ~= nil and not is_master_shard() then
        print("[Shard World Index] AdvanceWorldIndex must be called on the master shard.")
        cb(false)
        return false
    end

    opts = opts or {}

    local state = get_world_index_state(index)
    local target = get_world_index_target_from_opts(opts, state)
    if target == nil and opts.chapter ~= nil and type(state.level_sequence) == "table" then
        target = normalize_world_index_target(get_level_for_shard(state.level_sequence[opts.chapter], get_index_shard(index)))
    end
    if target ~= nil and
        (reject_unavailable_world_target(index, target, state.kind) or
        reject_current_world_target(index, target, state.kind)) then
        cb(false)
        return false
    end

    local function advance_after_save()
        request_secondary_world_index("AdvanceSecondaryWorldIndex", {
            kind = state.kind,
            reason = opts.reason,
            target = opts.target or opts.world or opts.level or opts.current_preset,
            file_id = opts.file_id,
            reuse_existing = opts.reuse_existing,
            keep_session = opts.keep_session,
            collect_player_sessions = false,
        }, function(secondary_ready, request)
            if not secondary_ready then
                print("[Shard World Index] Secondary shards did not prepare the target; Master will not change worlds.")
                cb(false)
                return
            end

            self:QueueNextWorld(index, opts, function(success)
                if not success then
                    abort_secondary_world_index_request(request)
                    cb(false)
                    return
                end
                commit_secondary_world_index_request(request, function(committed)
                    if committed then
                        restart_current_slot_after_shard_rpc(index,
                        {
                            world_index_transition = opts.reason or "advance",
                            world_index_file_id = get_world_index_state(index) ~= nil and get_world_index_state(index).file_id or opts.file_id,
                        })
                    end
                    cb(committed == true)
                end, opts.secondary_shard_wait_timeout or nil)
            end)
        end)
    end

    if TheWorld ~= nil and TheWorld.ismastersim then
        wait_for_secondary_shard_players_empty(function(players_ready)
            if not players_ready then
                cb(false)
                return
            end
            save_players()
            advance_after_save()
        end, opts.secondary_shard_wait_timeout or nil, opts.secondary_shard_wait_poll_interval or nil)
    else
        save_players()
        advance_after_save()
    end
    return true
end

function ShardWorldIndex:ReturnFromWorldIndex(index, reason, cb)
    index, reason, cb = resolve_index_args(self, index, reason, cb)
    cb = cb or noop
    if index == nil or not self:IsActive(index) then
        cb(false)
        return false
    end

    local function return_after_save()
        save_players()
        local player_sessions = collect_player_sessions()
        request_secondary_world_index("ReturnSecondaryWorldIndex", {
            reason = reason or "return",
        }, function(secondary_ready, request)
            if not secondary_ready then
                print("[Shard World Index] Secondary shards did not prepare the return; Master will not change worlds.")
                cb(false)
                return
            end

            self:ReturnToStoredWorld(index, reason or "return", function(success)
                if not success then
                    abort_secondary_world_index_request(request)
                    cb(false)
                    return
                end
                commit_secondary_world_index_request(request, function(committed)
                    if committed then
                        finalize_deferred_return(index, get_world_index_state(index), function(finalized)
                            if not finalized then
                                print("[Shard World Index] Deferred return cleanup will resume after restart.")
                            end
                            restart_current_slot_after_shard_rpc(index, { world_index_transition = reason or "return" })
                            cb(true)
                        end)
                    else
                        rollback_deferred_return(index, get_world_index_state(index), function()
                            cb(false)
                        end)
                    end
                end)
            end, player_sessions, { defer_cleanup = true })
        end)
    end

    if TheWorld ~= nil and TheWorld.ismastersim then
        wait_for_secondary_shard_players_empty(function(players_ready)
            if players_ready then
                return_after_save()
            else
                cb(false)
            end
        end)
    else
        return_after_save()
    end
    return true
end

function ShardWorldIndex:HasActiveSidecar(slot, cb)
    cb = cb or noop
    read_active_world_index_sidecar(slot, function(state)
        cb(state ~= nil)
    end)
end

function ShardWorldIndex:ReadActiveSidecar(slot, cb)
    read_active_world_index_sidecar(slot, cb)
end

function ShardWorldIndex:SwitchIndexToStoredWorld(index, state)
    index, state = resolve_index_args(self, index, state)
    local home = get_world_index_home_state(state)
    if home ~= nil then
        switch_index_to_existing_world(index, home)
        return true
    end
    return false
end
