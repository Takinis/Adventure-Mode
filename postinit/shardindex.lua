-- Minimal public API (call on the master shard):
--   StartShardAdventure({ level_sequence = { "RAINY", "WINTER", ... } })
--   StartShardAdventure({
--       level_sequence = {
--           { worldgen_preset = "ISLANDHOP", settings_preset = "ISLANDHOP", overrides = { day = "onlynight" } },
--       },
--   })
--   AdvanceShardAdventure()                -- next chapter, or return home if last
--   CompleteShardAdventure()               -- alias of AdvanceShardAdventure
--   ReturnFromShardAdventure(reason)       -- bail out to the main world now
--
-- Online players are copied into each generated adventure session so clients
-- resume their current character instead of being sent to character select. The
-- first adventure chapter keeps only character identity; adventure-to-adventure
-- transitions keep the current adventure inventory/components. The first
-- chapter also grants the character's start_inv once.
--
-- This does not edit the vanilla shardindex file format. Adventure state is
-- stored in a small sidecar file next to shardindex, then ShardIndex methods are
-- monkey patched to switch session_id/world options safely.

local AddGamePostInit = AddGamePostInit
local AddPlayerPostInit = AddPlayerPostInit

GLOBAL.setfenv(1, GLOBAL)

local ADVENTURE_INDEX_FILE = "adventure"
local DEFAULT_LEVEL_SEQUENCE = { "RAINY", "WINTER", "HUB", "ISLANDHOP", "TWOLANDS", "DARKNESS", "ENDING" }
local SHARD_RPC_NAMESPACE = "shard_adventure_postinit"
local SHARD_RPC_FORCE_MASTER = "ForcePlayersToMaster"
local SECONDARY_SHARD_WAIT_TIMEOUT = 30
local SECONDARY_SHARD_WAIT_POLL_INTERVAL = 0.5
local SECONDARY_SHARD_SETTLE_DELAY = 0.25
local ADVENTURE_DEATH_CHECK_TIMEOUT = 8
local ADVENTURE_DEATH_CHECK_POLL_INTERVAL = 0.25
local ADVENTURE_DEATH_CHECK_INITIAL_DELAY = 0.1

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

local function get_sidecar_filename(index)
    return index:GetShardIndexName().."_"..ADVENTURE_INDEX_FILE
end

local function read_sidecar(index, cb)
    cb = cb or noop

    local filename = get_sidecar_filename(index)
    local slot, shard = get_slot_and_shard(index)
    local function onload(load_success, str)
        if load_success and str ~= nil and #str > 0 then
            local success, data = RunInSandboxSafe(str)
            if success and type(data) == "table" then
                cb(data)
                return
            end
            print("[Adventure Mode] Failed to parse "..filename)
        end
        cb(nil)
    end

    if slot ~= nil and shard ~= nil then
        TheSim:GetPersistentStringInClusterSlot(slot, shard, filename, onload)
    else
        TheSim:GetPersistentString(filename, onload)
    end
end

local function write_sidecar(index, data, cb)
    cb = cb or noop

    local filename = get_sidecar_filename(index)
    local str = DataDumper(data or {}, nil, false)
    local slot, shard = get_slot_and_shard(index)
    if slot ~= nil and shard ~= nil then
        TheSim:SetPersistentStringInClusterSlot(slot, shard, filename, str, false, cb)
    else
        TheSim:SetPersistentString(filename, str, false, cb)
    end
end

local WORLDGENOVERRIDE_FILE = "../worldgenoverride.lua"

-- Read the raw worldgenoverride.lua text (verbatim) so it can be stashed and
-- written back later. Returns nil if the file is missing/empty.
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

-- Put the main world's worldgenoverride back (verbatim). If the main world had
-- none, write a disabled stub so a later regen won't pick up the adventure preset.
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

local player_starting_inventory = {}

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

local function player_is_dead_or_ghost(player)
    return player ~= nil and
        (player:HasTag("playerghost") or
        (player.components.health ~= nil and player.components.health:IsDead()))
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
        local file = TheNet:GetWorldSessionFileInClusterSlot(slot, "Master", session_id)
        if file ~= nil then
            TheSim:GetPersistentStringInClusterSlot(slot, "Master", file, function(load_success, str)
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

local function move_player_record_to_spawn(data, spawn, index)
    if type(data) ~= "table" then
        return nil
    end

    local offset = (index or 1) - 1
    local radius = offset > 0 and math.min(2 + offset, 8) or 0
    local angle = offset * 2.399963229728653 -- golden angle; keeps stacked players apart deterministically.

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

local function inject_player_sessions_into_world(index, state, session_identifier, savedata, cb)
    cb = cb or noop

    local sessions = state ~= nil and state.player_sessions or nil
    if sessions == nil or #sessions <= 0 or session_identifier == nil or session_identifier == "" or not TheNet:GetIsServer() then
        cb()
        return
    end

    local spawn = get_spawn_position_from_savedata_str(savedata)

    -- SerializeUserSession writes into the current engine session, so begin the
    -- freshly generated world session before copying cached player saves into it.
    TheNet:BeginSession(session_identifier)
    for i, session in ipairs(sessions) do
        if session.userid ~= nil and session.data ~= nil then
            local data = build_migrated_user_session_data(session, spawn, i)
            TheNet:SerializeUserSession(session.userid, data, false, nil, session.metadata or "")
        end
    end

    state.player_sessions = nil
    state.last_player_session_injected = session_identifier
    cb()
end

local give_adventure_first_chapter_start_inv

local function inject_late_joiners_into_main_world(index, state, cb)
    cb = cb or noop

    if state == nil or state.main == nil or state.main.session_id == nil or not TheNet:GetIsServer() then
        cb()
        return
    end

    local late_joiners = state.late_joiners
    if late_joiners == nil or next(late_joiners) == nil then
        cb()
        return
    end

    local sessions_by_userid = session_list_to_map(state.adventure_player_sessions)
    for _, session in ipairs(collect_player_sessions() or {}) do
        sessions_by_userid[session.userid] = session
    end

    local sessions = {}
    for userid in pairs(late_joiners) do
        local session = sessions_by_userid[userid]
        if session ~= nil and session.data ~= nil then
            table.insert(sessions, session)
        end
    end

    if #sessions <= 0 then
        cb()
        return
    end

    read_world_session_raw(index, state.main.session_id, function(savedata)
        local spawn = get_spawn_position_from_savedata_str(savedata)
        TheNet:BeginSession(state.main.session_id)
        for i, session in ipairs(sessions) do
            local data = build_migrated_user_session_data(session, spawn, i)
            TheNet:SerializeUserSession(session.userid, data, false, nil, session.metadata or "")
        end
        cb()
    end)
end

local function cache_adventure_player_session(inst, mark_late_joiner)
    if TheWorld == nil or not TheWorld.ismastersim or ShardGameIndex == nil or inst == nil or inst.userid == nil or inst.userid == "" then
        return
    end

    local state = ShardGameIndex:GetAdventureState()
    if state == nil or not state.active then
        return
    end

    if mark_late_joiner and (state.participants == nil or not state.participants[inst.userid]) then
        state.late_joiners = state.late_joiners or {}
        state.late_joiners[inst.userid] = true
    end

    local session = get_player_save_session(inst)
    if session == nil then
        return
    end

    state.adventure_player_sessions = state.adventure_player_sessions or {}
    local replaced = false
    for i, existing in ipairs(state.adventure_player_sessions) do
        if existing.userid == inst.userid then
            state.adventure_player_sessions[i] = session
            replaced = true
            break
        end
    end
    if not replaced then
        table.insert(state.adventure_player_sessions, session)
    end

    state.updated_at = os.time()
    write_sidecar(ShardGameIndex, state)
end

local function on_adventure_player_activated(inst)
    cache_adventure_player_session(inst, true)
    give_adventure_first_chapter_start_inv(inst)
end

local function on_adventure_player_deactivated(inst)
    cache_adventure_player_session(inst, false)
end

local function all_adventure_players_dead()
    if TheWorld == nil or not TheWorld.ismastersim then
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

    if TheShard ~= nil and TheShard.GetSecondaryShardPlayerCounts ~= nil and is_master_shard() then
        local secondary_players, secondary_ghosts = TheShard:GetSecondaryShardPlayerCounts(USERFLAGS.IS_GHOST)
        secondary_players = secondary_players or 0
        secondary_ghosts = secondary_ghosts or 0
        total = total + secondary_players
        alive = alive + math.max(secondary_players - secondary_ghosts, 0)
    end

    return total > 0 and alive <= 0
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

local function send_force_players_to_master_rpc()
    if SendModRPCToShard == nil or GetShardModRPC == nil or ShardList == nil or TheShard == nil then
        return
    end

    local rpc = GetShardModRPC(SHARD_RPC_NAMESPACE, SHARD_RPC_FORCE_MASTER)
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
            print("[Adventure Mode] Timed out waiting for secondary shard players to return to master. Remaining secondary players: "..tostring(secondary_players))
            cb()
            return
        end

        TheWorld:DoTaskInTime(poll_interval, poll)
    end

    poll()
end

local function register_shard_rpc()
    AddShardModRPCHandler(SHARD_RPC_NAMESPACE, SHARD_RPC_FORCE_MASTER, function()
        force_local_players_to_master()
    end)
end

register_shard_rpc()

function give_adventure_first_chapter_start_inv(inst)
    if TheWorld == nil or not TheWorld.ismastersim or ShardGameIndex == nil then
        return
    end

    local state = ShardGameIndex:GetAdventureState()
    if state == nil or
        not state.active or
        state.chapter ~= 1 or
        not state.first_chapter_start_inv_pending or
        inst.userid == nil or
        inst.userid == "" then
        return
    end

    if state.participants == nil or not state.participants[inst.userid] then
        return
    end

    state.first_chapter_start_inv_given = state.first_chapter_start_inv_given or {}
    if state.first_chapter_start_inv_given[inst.userid] then
        return
    end

    local items = player_starting_inventory[inst.prefab]
    if items ~= nil and #items > 0 and inst.components.inventory ~= nil then
        require("prefabs/player_common_extensions").GivePlayerStartingItems(inst, items, nil)
    end

    state.first_chapter_start_inv_given[inst.userid] = true
    write_sidecar(ShardGameIndex, state)
end

local function restart_current_slot(extra_params)
    local params = extra_params or {}
    params.reset_action = RESET_ACTION.LOAD_SLOT
    params.save_slot = ShardGameIndex:GetSlot()
    StartNextInstance(params)
end

-- Deep copy into a plain table: drops metatables and skips function values so the
-- result round-trips through DataDumper without needing loadstring on load. Level
-- presets (GetDataForWorldGenID / GetDefaultLevelData) are Class instances whose
-- metatable holds a compiled _ctor; DataDumper serializes that as loadstring(bytecode),
-- and ShardIndex:Load's RunInSandbox has no loadstring -> fatal "attempt to call
-- global 'loadstring'" that bricks the slot. world.options must be plain data.
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

-- Resolve the worldgen options table for an adventure level. A level may be a
-- preset id string, a worldgenoverride-like table, or { level_options = ... }.
-- Falls back to the game mode's default level when the preset can't be found.
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

-- Force the adventure level's worldgenoverride. Without this, SetServerShardData
-- re-applies the MAIN world's worldgenoverride on the next boot and we generate
-- the wrong world. When both presets are supplied, GetWorldgenOverride does a
-- full override; otherwise the generated override merges onto self.world.options.
local function write_adventure_worldgenoverride(index, level, cb)
    write_worldgenoverride_str(index, DataDumper(build_worldgenoverride_data(level), nil, false).."\n", cb)
end

local function get_adventure_state(index)
    return index.adventure_state
end

local function set_adventure_state(index, state)
    index.adventure_state = state
end

local function patch_shard_index()
    if ShardIndex == nil or ShardIndex._adventure_postinit_patched then
        return
    end
    ShardIndex._adventure_postinit_patched = true

    local _Load = ShardIndex.Load
    function ShardIndex:Load(callback)
        _Load(self, function(...)
            local args = { ... }
            read_sidecar(self, function(state)
                set_adventure_state(self, state)
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
            read_sidecar(self, function(state)
                set_adventure_state(self, state)
                if callback ~= nil then
                    callback(unpack(args))
                end
            end)
        end)
    end

    local _NewShardInSlot = ShardIndex.NewShardInSlot
    function ShardIndex:NewShardInSlot(slot, shard)
        _NewShardInSlot(self, slot, shard)
        set_adventure_state(self, nil)
    end

    local _Delete = ShardIndex.Delete
    function ShardIndex:Delete(cb, save_options)
        local state = get_adventure_state(self)
        if save_options and state ~= nil and state.active then
            _Delete(self, function(...)
                local args = { ... }
                set_adventure_state(self, state)
                write_sidecar(self, state, function()
                    if cb ~= nil then
                        cb(unpack(args))
                    end
                end)
            end, save_options)
            return
        end

        set_adventure_state(self, nil)
        write_sidecar(self, nil, function()
            _Delete(self, cb, save_options)
        end)
    end

    local _OnGenerateNewWorld = ShardIndex.OnGenerateNewWorld
    function ShardIndex:OnGenerateNewWorld(savedata, metadataStr, session_identifier, cb)
        _OnGenerateNewWorld(self, savedata, metadataStr, session_identifier, function(...)
            local args = { ... }
            local state = get_adventure_state(self)
            if state ~= nil and state.active then
                state.current_session_id = session_identifier
                state.updated_at = os.time()
                inject_player_sessions_into_world(self, state, session_identifier, savedata, function()
                    write_sidecar(self, state, function()
                        if cb ~= nil then
                            cb(unpack(args))
                        end
                    end)
                end)
            elseif cb ~= nil then
                cb(unpack(args))
            end
        end)
    end

    function ShardIndex:BuildPlaylist()
        
    end

    function ShardIndex:IsAdventureActive()
        local state = get_adventure_state(self)
        return state ~= nil and state.active == true
    end

    function ShardIndex:GetAdventureState()
        return get_adventure_state(self)
    end

    function ShardIndex:AdventureBegin(opts, cb)
        cb = cb or noop
        opts = opts or {}

        if self:IsAdventureActive() then
            print("[Adventure Mode] Adventure already active.")
            cb(false)
            return
        end

        local main_session = self:GetSession()
        if main_session == nil or main_session == "" then
            print("[Adventure Mode] Cannot begin adventure without a main world session.")
            cb(false)
            return
        end

        local level_sequence = opts.level_sequence or deepcopy_safe(DEFAULT_LEVEL_SEQUENCE)
        if #level_sequence == 0 then
            print("[Adventure Mode] Empty level_sequence.")
            cb(false)
            return
        end

        local first_preset = level_sequence[1]

        -- Stash the MAIN world's worldgenoverride verbatim before we overwrite it,
        -- so AdventureReturnToMainWorld can put it back exactly as it was.
        read_worldgenoverride_raw(self, function(main_wgo)
            local main_player_sessions = opts.player_sessions or collect_player_sessions()
            local state =
            {
                active = true,
                reason = "begin",
                sequence_id = opts.sequence_id or "default",
                started_at = os.time(),
                updated_at = os.time(),

                level_sequence = deepcopy_safe(level_sequence),
                chapter = 1,
                current_preset = first_preset,
                current_session_id = nil,
                player_sessions = get_character_only_sessions(main_player_sessions),
                participants = sessions_to_userid_map(main_player_sessions),
                late_joiners = {},
                adventure_player_sessions = {},
                first_chapter_start_inv_pending = true,
                first_chapter_start_inv_given = {},

                main =
                {
                    session_id = main_session,
                    worldgenoverride = main_wgo,
                    world = deepcopy_safe(self.world),
                    server = deepcopy_safe(self.server),
                    enabled_mods = deepcopy_safe(self.enabled_mods),
                    return_position = opts.return_position or get_return_position(),
                    player_sessions = main_player_sessions,
                },
            }

            set_adventure_state(self, state)
            self.world = { options = resolve_level_options(first_preset) }
            self.session_id = nil
            self:MarkDirty()

            write_adventure_worldgenoverride(self, first_preset, function()
                self:Save(function()
                    write_sidecar(self, state, function()
                        cb(true)
                    end)
                end)
            end)
        end)
    end

    -- Advance to the next chapter in the sequence, generating a fresh world. If the
    -- current chapter is the last one, return to the main world instead.
    function ShardIndex:AdventureAdvance(opts, cb)
        if type(opts) == "function" and cb == nil then
            cb = opts
            opts = nil
        end
        cb = cb or noop
        opts = opts or {}

        local state = get_adventure_state(self)
        if state == nil or not state.active or state.main == nil then
            print("[Adventure Mode] No active adventure to advance.")
            cb(false)
            return
        end

        local next_chapter = (state.chapter or 1) + 1
        if next_chapter > #state.level_sequence then
            return self:AdventureReturnToMainWorld("complete", cb)
        end

        -- Delete the world we are leaving so adventure sessions don't pile up. Never
        -- touch the stashed main session.
        local leaving = state.current_session_id
        if leaving ~= nil and leaving ~= "" and leaving ~= state.main.session_id then
            TheNet:DeleteSession(leaving)
        end

        local next_preset = state.level_sequence[next_chapter]
        state.chapter = next_chapter
        state.current_preset = next_preset
        state.current_session_id = nil
        local player_sessions = opts.player_sessions or collect_player_sessions()
        state.player_sessions = merge_session_lists(player_sessions, state.adventure_player_sessions)
        state.adventure_player_sessions = deepcopy_safe(state.player_sessions) or {}
        state.first_chapter_start_inv_pending = false
        state.updated_at = os.time()

        self.world = { options = resolve_level_options(next_preset) }
        self.session_id = nil
        self:MarkDirty()

        write_adventure_worldgenoverride(self, next_preset, function()
            self:Save(function()
                write_sidecar(self, state, function()
                    set_adventure_state(self, state)
                    cb(true, next_chapter)
                end)
            end)
        end)
    end

    function ShardIndex:AdventureComplete(cb)
        return self:AdventureAdvance(cb)
    end

    function ShardIndex:AdventureReturnToMainWorld(reason, cb)
        cb = cb or noop

        local state = get_adventure_state(self)
        if state == nil or not state.active or state.main == nil then
            print("[Adventure Mode] No active adventure to return from.")
            cb(false)
            return
        end

        inject_late_joiners_into_main_world(self, state, function()
            -- Delete the adventure world we are leaving; keep the stashed main session.
            local leaving = state.current_session_id
            if leaving ~= nil and leaving ~= "" and leaving ~= state.main.session_id then
                TheNet:DeleteSession(leaving)
            end

            self.session_id = state.main.session_id
            self.world = deepcopy_safe(state.main.world) or { options = {} }
            self.server = deepcopy_safe(state.main.server) or {}
            self.enabled_mods = deepcopy_safe(state.main.enabled_mods) or {}
            state.active = false
            state.finished_at = os.time()
            state.return_reason = reason or "return"
            self:MarkDirty()

            -- Restore the main world's worldgenoverride so a later main-world regen
            -- doesn't pick up the adventure preset.
            restore_worldgenoverride(self, state.main.worldgenoverride, function()
                self:Save(function()
                    write_sidecar(self, state, function()
                        set_adventure_state(self, state)
                        cb(true)
                    end)
                end)
            end)
        end)
    end
end

if ShardIndex ~= nil then
    patch_shard_index()
elseif AddGamePostInit ~= nil then
    AddGamePostInit(patch_shard_index)
end

function StartShardAdventure(opts)
    if ShardGameIndex == nil then
        return false
    end
    if TheShard ~= nil and not is_master_shard() then
        print("[Adventure Mode] StartShardAdventure must be called on the master shard.")
        return false
    end

    local function begin_after_save()
        ShardGameIndex:AdventureBegin(opts, function(success)
            if success then
                restart_current_slot({ adventure_transition = "begin" })
            end
        end)
    end

    if TheWorld ~= nil and TheWorld.ismastersim then
        send_force_players_to_master_rpc()
        wait_for_secondary_shard_players_empty(function()
            ShardGameIndex:SaveCurrent(begin_after_save)
        end, opts ~= nil and opts.secondary_shard_wait_timeout or nil, opts ~= nil and opts.secondary_shard_wait_poll_interval or nil)
    else
        save_players()
        begin_after_save()
    end
    return true
end

function AdvanceShardAdventure(opts)
    if ShardGameIndex == nil or not ShardGameIndex:IsAdventureActive() then
        return false
    end

    save_players()
    ShardGameIndex:AdventureAdvance(opts, function(success)
        if success then
            restart_current_slot({ adventure_transition = "advance" })
        end
    end)
    return true
end

function CompleteShardAdventure(opts)
    return AdvanceShardAdventure(opts)
end

function ReturnFromShardAdventure(reason)
    if ShardGameIndex == nil or not ShardGameIndex:IsAdventureActive() then
        return false
    end

    save_players()
    ShardGameIndex:AdventureReturnToMainWorld(reason or "return", function(success)
        if success then
            restart_current_slot({ adventure_transition = reason or "return" })
        end
    end)
    return true
end

local adventure_death_check_task = nil

local function schedule_adventure_death_check(inst)
    if adventure_death_check_task ~= nil then
        return
    end

    local started_at = GetTime()
    local function check()
        adventure_death_check_task = nil

        if ShardGameIndex == nil or not ShardGameIndex:IsAdventureActive() then
            return
        end

        if all_adventure_players_dead() then
            ReturnFromShardAdventure("death")
            return
        end

        if GetTime() - started_at < ADVENTURE_DEATH_CHECK_TIMEOUT and TheWorld ~= nil then
            adventure_death_check_task = TheWorld:DoTaskInTime(ADVENTURE_DEATH_CHECK_POLL_INTERVAL, check)
        end
    end

    local scheduler = TheWorld or inst
    if scheduler ~= nil then
        adventure_death_check_task = scheduler:DoTaskInTime(ADVENTURE_DEATH_CHECK_INITIAL_DELAY, check)
    end
end

local function on_player_death(inst)
    if TheWorld == nil or not TheWorld.ismastersim then
        return
    end
    if ShardGameIndex ~= nil and ShardGameIndex:IsAdventureActive() then
        schedule_adventure_death_check(inst)
    end
end

if AddPlayerPostInit ~= nil then
    AddPlayerPostInit(function(inst)
        if inst.prefab ~= nil and inst.starting_inventory ~= nil then
            player_starting_inventory[inst.prefab] = deepcopy_safe(inst.starting_inventory)
        end

        if TheWorld == nil or not TheWorld.ismastersim then
            return
        end

        inst:ListenForEvent("death", on_player_death)
        inst:ListenForEvent("ms_becameghost", on_player_death)
        inst:ListenForEvent("playeractivated", on_adventure_player_activated)
        inst:ListenForEvent("playerdeactivated", on_adventure_player_deactivated)
        inst:DoTaskInTime(0, on_adventure_player_activated)
    end)
end


local LEVEL_DEFS = {
    { id = "RAINY",      min_playlist_position = 1, max_playlist_position = 3 },
    { id = "WINTER",     min_playlist_position = 1, max_playlist_position = 4 },
    { id = "HUB",        min_playlist_position = 1, max_playlist_position = 4 },
    { id = "ISLANDHOP",  min_playlist_position = 1, max_playlist_position = 4 },
    { id = "TWOLANDS",   min_playlist_position = 3, max_playlist_position = 4 },
    { id = "DARKNESS",   min_playlist_position = CAMPAIGN_LENGTH,     max_playlist_position = CAMPAIGN_LENGTH },
    { id = "ENDING",     min_playlist_position = CAMPAIGN_LENGTH + 1, max_playlist_position = CAMPAIGN_LENGTH + 1 },
}

function ShardIndex:BuildAdventurePlaylist()
    local pool = {}
    for _, def in ipairs(LEVEL_DEFS) do
        if def.id ~= "DARKNESS" and def.id ~= "ENDING" then
            table.insert(pool, def)
        end
    end

    shuffleArray(pool)

    local playlist = {}
    for position = 1, CAMPAIGN_LENGTH - 1 do
        for i, def in ipairs(pool) do
            if def.min_playlist_position <= position and def.max_playlist_position >= position then
                playlist[position] = def.id
                table.remove(pool, i)
                break
            end
        end
    end

    playlist[CAMPAIGN_LENGTH]     = "DARKNESS"
    playlist[CAMPAIGN_LENGTH + 1] = "ENDING"

    print("Adventure Mode: built adventure playlist")
    for i = 1, #playlist do
        print("  Chapter " .. tostring(i) .. ": " .. tostring(playlist[i]))
    end

    return playlist
end
