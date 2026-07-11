-- Adventure state manager for ShardIndex.
-- Generic world switching lives in ShardWorldIndex; this class owns chapter
-- rules, adventure player sessions, and shard sync flow.

GLOBAL.setfenv(1, GLOBAL)

local ShardWorldIndex = ShardWorldIndex

ShardAdventureIndex = Class(function(self, index)
    self.index = index
end)

local ADVENTURE_DEATH_CHECK_POLL_INTERVAL = 0.25
local ADVENTURE_DEATH_CHECK_INITIAL_DELAY = 0.1
local ADVENTURE_WORLD_SWITCH_FILE_ID = "adventure"
local ADVENTURE_DARKNESS_LEVEL = "DARKNESS"
local ADVENTURE_ENDING_LEVEL = "ENDING"
local ADVENTURE_LEVEL_COUNT = 4
local ADVENTURE_LEVELS =
{
    RAINY = true,
    WINTER = true,
    HUB = true,
    ISLANDHOP = true,
    TWOLANDS = true,
}

local function get_adventure_playlist_level_id(level)
    if type(level) == "table" then
        level = level.id
    end
    return type(level) == "string" and level ~= "" and level or nil
end

local function get_adventure_playlist_level_key(level)
    local id = get_adventure_playlist_level_id(level)
    return id ~= nil and string.upper(id) or nil
end

local function get_adventure_playlist_position(value, default)
    value = tonumber(value)
    return value ~= nil and math.floor(value) or default
end

local function order_adventure_playlist_levels(levels)
    local count = #levels
    if count == 0 then
        return {}
    elseif count == 1 then
        return { levels[1].id }
    end

    local pending = {}
    for _, level in ipairs(levels) do
        local min_position = math.max(get_adventure_playlist_position(level.min_playlist_position, 1), 1)
        local max_position = math.max(get_adventure_playlist_position(level.max_playlist_position, count), min_position)

        min_position = math.min(min_position, count)
        max_position = math.min(max_position, count)

        table.insert(pending, {
            id = level.id,
            min_position = min_position,
            preferred_position = math.random(min_position, max_position),
            tie_breaker = math.random(1, 1000000),
        })
    end

    table.sort(pending, function(a, b)
        if a.preferred_position ~= b.preferred_position then
            return a.preferred_position < b.preferred_position
        end
        if a.tie_breaker ~= b.tie_breaker then
            return a.tie_breaker < b.tie_breaker
        end
        return a.id < b.id
    end)

    local ordered = {}
    for position = 1, count do
        local selected = nil
        for i, level in ipairs(pending) do
            if level.min_position <= position then
                selected = i
                break
            end
        end

        -- Conflicting position preferences must not make a registered level disappear.
        selected = selected or 1
        table.insert(ordered, table.remove(pending, selected).id)
    end

    return ordered
end

local function build_adventure_playlist(levels)
    local core_levels = {}
    local extension_levels = {}
    local levels_by_key = {}
    local seen = {}
    local has_darkness = false
    local has_ending = false

    for _, level in ipairs(levels) do
        local id = get_adventure_playlist_level_id(level)
        local key = get_adventure_playlist_level_key(level)
        if key == ADVENTURE_DARKNESS_LEVEL then
            has_darkness = true
        elseif key == ADVENTURE_ENDING_LEVEL then
            has_ending = true
        elseif id ~= nil and not seen[key] then
            seen[key] = true
            local playlist_level = {
                id = id,
                min_playlist_position = type(level) == "table" and level.min_playlist_position or nil,
                max_playlist_position = type(level) == "table" and level.max_playlist_position or nil,
            }
            levels_by_key[key] = playlist_level
            table.insert(ADVENTURE_LEVELS[key] and core_levels or extension_levels, playlist_level)
        end
    end

    if not has_darkness or not has_ending then
        local missing = not has_darkness and ADVENTURE_DARKNESS_LEVEL or ADVENTURE_ENDING_LEVEL
        return nil, "missing terminal adventure level " .. missing
    end

    local regular_levels = {}
    local ordered_core_levels = order_adventure_playlist_levels(core_levels)
    for i = 1, math.min(ADVENTURE_LEVEL_COUNT, #ordered_core_levels) do
        table.insert(regular_levels, levels_by_key[string.upper(ordered_core_levels[i])])
    end
    for _, level in ipairs(extension_levels) do
        table.insert(regular_levels, level)
    end

    local playlist = order_adventure_playlist_levels(regular_levels)
    table.insert(playlist, ADVENTURE_DARKNESS_LEVEL)
    table.insert(playlist, ADVENTURE_ENDING_LEVEL)
    return playlist
end

local function normalize_adventure_playlist(level_sequence)
    if type(level_sequence) ~= "table" then
        return nil, "level_sequence must be a table"
    end

    local normalized = {}
    for i = 1, #level_sequence do
        local level = level_sequence[i]
        if type(level) ~= "table" and get_adventure_playlist_level_id(level) == nil then
            return nil, "invalid level id at position " .. tostring(i)
        end

        local key = get_adventure_playlist_level_key(level)
        if key ~= ADVENTURE_DARKNESS_LEVEL and key ~= ADVENTURE_ENDING_LEVEL then
            table.insert(normalized, level)
        end
    end

    table.insert(normalized, ADVENTURE_DARKNESS_LEVEL)
    table.insert(normalized, ADVENTURE_ENDING_LEVEL)
    return normalized
end

local function NOOP()
    ShardWorldIndex:Noop()
end

local function read_sidecar(index, cb)
    cb = cb or NOOP
    index.worldindex:ReadSidecar(cb, ADVENTURE_WORLD_SWITCH_FILE_ID)
end

local function write_sidecar(index, data, cb)
    cb = cb or NOOP
    index.worldindex:WriteSidecar(data, cb, ADVENTURE_WORLD_SWITCH_FILE_ID)
end

local set_adventure_state
local get_adventure_state

local player_starting_inventory = {}

local function player_is_dead_or_ghost(player)
    return player ~= nil and
        (player:HasTag("playerghost") or
        (player.components.health ~= nil and player.components.health:IsDead()))
end

local give_adventure_first_chapter_start_inv

local function inject_late_joiners_into_main_world(index, state, cb)
    cb = cb or NOOP

    if state == nil or state.secondary or state.main == nil or state.main.session_id == nil or not TheNet:GetIsServer() then
        cb()
        return
    end

    local late_joiners = state.late_joiners
    if late_joiners == nil or next(late_joiners) == nil then
        cb()
        return
    end

    local sessions_by_userid = ShardWorldIndex:SessionListToMap(state.adventure_player_sessions)
    for _, session in ipairs(ShardWorldIndex:CollectPlayerSessions() or {}) do
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

    index.worldindex:InjectPlayerSessionsIntoExistingWorld(state.main.session_id, sessions, cb)
end

local function cache_adventure_player_session(index, inst, mark_late_joiner)
    if TheWorld == nil or not TheWorld.ismastersim or index == nil or inst == nil or inst.userid == nil or inst.userid == "" then
        return
    end

    local state = get_adventure_state(index)
    if state == nil or not state.active or state.secondary then
        return
    end

    if mark_late_joiner and (state.participants == nil or not state.participants[inst.userid]) then
        state.late_joiners = state.late_joiners or {}
        state.late_joiners[inst.userid] = true
    end

    local session = ShardWorldIndex:GetPlayerSaveSession(inst)
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
    write_sidecar(index, state)
end

local function on_adventure_player_activated(index, inst)
    cache_adventure_player_session(index, inst, true)
    give_adventure_first_chapter_start_inv(index, inst)
end

local function on_adventure_player_deactivated(index, inst)
    cache_adventure_player_session(index, inst, false)
end

local function all_adventure_players_dead()
    if TheWorld == nil or not TheWorld.ismastersim or not ShardWorldIndex:IsMasterShard() then
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

    local secondary_players, secondary_ghosts = ShardWorldIndex:GetSecondaryShardPlayerCounts()
    total = total + secondary_players
    alive = alive + math.max(secondary_players - secondary_ghosts, 0)

    return total > 0 and alive <= 0
end

local function send_force_players_to_master_rpc()
    ShardWorldIndex:SendForcePlayersToMasterRPC("AdventureMode", "ForcePlayersToMaster")
end

local function send_secondary_adventure_rpc(name, data)
    ShardWorldIndex:SendRPCToOtherSecondaryShards("AdventureMode", name, data)
end

local function send_master_adventure_rpc(name, data)
    ShardWorldIndex:SendRPCToMasterShard("AdventureMode", name, data)
end

give_adventure_first_chapter_start_inv = function(index, inst)
    if TheWorld == nil or not TheWorld.ismastersim or index == nil then
        return
    end

    local state = get_adventure_state(index)
    if state == nil or
        not state.active or
        state.chapter ~= 1 or
        not state.first_chapter_start_inv_pending or
        inst == nil or
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
    write_sidecar(index, state)
end

local function restart_current_slot_after_shard_rpc(index, extra_params)
    extra_params = extra_params or {}
    extra_params.world_switch_file_id = ADVENTURE_WORLD_SWITCH_FILE_ID
    index.worldindex:RestartCurrentSlotAfterShardRPC(extra_params)
end

local adventure_death_check_task = nil

local function schedule_adventure_death_check(index, inst)
    if adventure_death_check_task ~= nil then
        return
    end

    local function check()
        adventure_death_check_task = nil

        local state = get_adventure_state(index)
        if state == nil or not state.active then
            return
        end

        if all_adventure_players_dead() then
            index.adventure:ReturnFromShard("death")
            return
        end

        if TheWorld ~= nil then
            adventure_death_check_task = TheWorld:DoTaskInTime(ADVENTURE_DEATH_CHECK_POLL_INTERVAL, check)
        end
    end

    local scheduler = TheWorld or inst
    if scheduler ~= nil then
        adventure_death_check_task = scheduler:DoTaskInTime(ADVENTURE_DEATH_CHECK_INITIAL_DELAY, check)
    end
end

local function on_player_death(index, inst)
    if TheWorld == nil or not TheWorld.ismastersim or not ShardWorldIndex:IsMasterShard() then
        return
    end
    local state = get_adventure_state(index)
    if state ~= nil and state.active then
        schedule_adventure_death_check(index, inst)
    end
end

local function get_adventure_preset_id(preset)
    if type(preset) == "table" then
        return preset.id or preset.worldgen_preset or preset.preset or preset.settings_preset
    end
    return preset
end

get_adventure_state = function(index)
    if TheWorld ~= nil and not TheWorld.ismastersim and TheWorld.net ~= nil and
        TheWorld.net.components ~= nil and TheWorld.net.components.adventure ~= nil then
        local state = TheWorld.net.components.adventure:GetState()
        if state ~= nil then
            return state
        end
    end

    if TheWorld ~= nil and not TheWorld.ismastersim and TheWorld.topology ~= nil then
        local state = TheWorld.topology.adventure_state
        if state ~= nil then
            return state
        end
    end

    local state = index.worldindex:GetState(ADVENTURE_WORLD_SWITCH_FILE_ID)
    if state ~= nil then
        return state
    end

    return index.adventure_state
end

local function get_adventure_preset(index)
    local state = get_adventure_state(index)
    return get_adventure_preset_id(state ~= nil and state.current_preset or nil)
end

local function get_adventure_level(index)
    local state = get_adventure_state(index)
    return state ~= nil and state.active == true and get_adventure_preset_id(state.current_preset) or nil
end

local function get_adventure_chapter(state)
    local chapter = state ~= nil and state.chapter or nil
    return type(chapter) == "number" and chapter or nil
end

local function has_current_adventure_maxwell_intro_played(state, userid)
    local chapter = get_adventure_chapter(state)
    local played_chapters = state ~= nil and state.maxwell_intro_played_chapters or nil
    local played = type(played_chapters) == "table" and played_chapters[chapter] or nil
    return state ~= nil and
        state.active == true and
        chapter ~= nil and
        type(userid) == "string" and
        userid ~= "" and
        type(played) == "table" and
        played[userid] == true
end

set_adventure_state = function(index, state)
    index.adventure_state = state

    index.worldindex:SetState(state, ADVENTURE_WORLD_SWITCH_FILE_ID)

    if TheWorld ~= nil and TheWorld.ismastersim and TheWorld.net ~= nil and
        TheWorld.net.components ~= nil and TheWorld.net.components.adventure ~= nil then
        TheWorld.net.components.adventure:SetState(state)
    end
end

local function get_maxwell_throne_puppet_record(record)
    if type(record) ~= "table" then
        return nil
    end

    local character = record.character
    if type(character) ~= "string" or character == "" then
        return nil
    end

    local build = record.build
    if type(build) ~= "string" or build == "" then
        build = character
    end

    return
    {
        character = character,
        build = build,
        userid = type(record.userid) == "string" and record.userid or nil,
    }
end

local function get_adventure_maxwell_throne_puppet(index)
    local state = get_adventure_state(index)
    return state ~= nil and get_maxwell_throne_puppet_record(state.maxwell_throne_puppet) or nil
end

local function set_adventure_maxwell_throne_puppet(index, record)
    local state = get_adventure_state(index)
    if state == nil then
        return false
    end

    local puppet = get_maxwell_throne_puppet_record(record)
    if puppet == nil then
        return false
    end

    state.maxwell_throne_puppet = puppet
    state.updated_at = os.time()
    write_sidecar(index, state)
    return true
end

local function mark_current_adventure_maxwell_intro_played(index, userid)
    local state = get_adventure_state(index)
    local chapter = get_adventure_chapter(state)
    if state == nil or not state.active or chapter == nil or type(userid) ~= "string" or userid == "" then
        return false
    end

    state.maxwell_intro_played_chapters = state.maxwell_intro_played_chapters or {}
    local played = state.maxwell_intro_played_chapters[chapter]

    if type(played) ~= "table" then
        played = {}
        state.maxwell_intro_played_chapters[chapter] = played
    end

    if played[userid] then
        return true
    end

    played[userid] = true
    state.updated_at = os.time()
    write_sidecar(index, state)
    return true
end

function ShardAdventureIndex:ForceLocalPlayersToMaster()
    ShardWorldIndex:ForceLocalPlayersToMaster()
end

function ShardAdventureIndex:IsMasterShard()
    return ShardWorldIndex:IsMasterShard()
end

function ShardAdventureIndex:GetSecondaryShardPlayerCount()
    return ShardWorldIndex:GetSecondaryShardPlayerCount()
end

function ShardAdventureIndex:WaitForSecondaryShardPlayersEmpty(cb, timeout, poll_interval)
    ShardWorldIndex:WaitForSecondaryShardPlayersEmpty(cb, timeout, poll_interval)
end

function ShardAdventureIndex:CachePlayerSession(inst, mark_late_joiner)
    cache_adventure_player_session(self.index, inst, mark_late_joiner)
end

function ShardAdventureIndex:OnPlayerActivated(inst)
    on_adventure_player_activated(self.index, inst)
end

function ShardAdventureIndex:OnPlayerDeactivated(inst)
    on_adventure_player_deactivated(self.index, inst)
end

function ShardAdventureIndex:OnPlayerDeath(inst)
    on_player_death(self.index, inst)
end

function ShardAdventureIndex:StartDeathCheck(inst)
    if TheWorld ~= nil and TheWorld.ismastersim and ShardWorldIndex:IsMasterShard() and self:IsActive() then
        schedule_adventure_death_check(self.index, inst or TheWorld)
    end
end

function ShardAdventureIndex:RememberStartingInventory(inst)
    if inst ~= nil and inst.prefab ~= nil and inst.starting_inventory ~= nil then
        player_starting_inventory[inst.prefab] = ShardWorldIndex:DeepCopy(inst.starting_inventory)
    end
end

function ShardAdventureIndex:LoadSidecar(cb)
    return self.index.worldindex:LoadSidecar(cb, ADVENTURE_WORLD_SWITCH_FILE_ID)
end

function ShardAdventureIndex:ClearSidecar(cb)
    return self.index.worldindex:ClearSidecar(cb, ADVENTURE_WORLD_SWITCH_FILE_ID)
end

function ShardAdventureIndex:NeedsGenerationOnLoad()
    return self.index.worldindex:NeedsGenerationOnLoad()
end

function ShardAdventureIndex:ReservesSlot()
    return self.index.worldindex:ReservesSlot()
end

function ShardAdventureIndex:PreservePendingGenerationOnDelete(save_options, cb)
    return self.index.worldindex:PreservePendingGenerationOnDelete(save_options, cb)
end

function ShardAdventureIndex:PrepareDelete(save_options, cb)
    return self.index.worldindex:PrepareDelete(save_options, cb)
end

function ShardAdventureIndex:PrepareSetServerShardData(cb)
    return self.index.worldindex:PrepareSetServerShardData(cb)
end

function ShardAdventureIndex:BeforeGenerateNewWorld(savedata, metadataStr, session_identifier)
    return self.index.worldindex:BeforeGenerateNewWorld(savedata, metadataStr, session_identifier)
end

function ShardAdventureIndex:AfterGenerateNewWorld(savedata, session_identifier, cb)
    return self.index.worldindex:AfterGenerateNewWorld(savedata, session_identifier, cb)
end

function ShardAdventureIndex:BuildPlaylist()
    local Levels = require("map/levels")
    local registered_levels = {}
    for _, level_entry in ipairs(Levels.GetLevelList(LEVELTYPE.ADVENTURE)) do
        local level_id = level_entry.data
        -- GetLevelList also appends custom presets regardless of level type.
        if Levels.GetTypeForLevelID(level_id) == LEVELTYPE.ADVENTURE then
            local level = Levels.GetDataForLevelID(level_id)
            if level ~= nil then
                table.insert(registered_levels, level)
            end
        end
    end

    local playlist, error_message = build_adventure_playlist(registered_levels)
    if playlist == nil then
        print("[Adventure Mode] Cannot build playlist: " .. tostring(error_message) .. ".")
        return nil
    end

    print("[Adventure Mode] Built adventure playlist.")
    for i = 1, #playlist do
        print("  Chapter " .. tostring(i) .. ": " .. tostring(playlist[i]))
    end

    return playlist
end

function ShardAdventureIndex:IsActive()
    local state = get_adventure_state(self.index)
    return state ~= nil and state.active == true
end

function ShardAdventureIndex:GetState()
    return get_adventure_state(self.index)
end

function ShardAdventureIndex:GetPreset()
    return get_adventure_preset(self.index)
end

function ShardAdventureIndex:GetLevel()
    return get_adventure_level(self.index)
end

function ShardAdventureIndex:IsLevel(level)
    return self:GetLevel() == level
end

function ShardAdventureIndex:GetMaxwellThronePuppet()
    return get_adventure_maxwell_throne_puppet(self.index)
end

function ShardAdventureIndex:SetMaxwellThronePuppet(record)
    return set_adventure_maxwell_throne_puppet(self.index, record)
end

function ShardAdventureIndex:IsCurrentMaxwellIntroPlayed(userid)
    return has_current_adventure_maxwell_intro_played(get_adventure_state(self.index), userid)
end

function ShardAdventureIndex:MarkCurrentMaxwellIntroPlayed(userid)
    return mark_current_adventure_maxwell_intro_played(self.index, userid)
end

function ShardAdventureIndex:Begin(opts, cb)
    local index = self.index
    local worldindex = index.worldindex
    cb = cb or NOOP
    opts = opts or {}

    if self:IsActive() then
        print("[Adventure Mode] Adventure already active.")
        cb(false)
        return
    end

    local main_session = index:GetSession()
    if main_session == nil or main_session == "" then
        print("[Adventure Mode] Cannot begin adventure without a main world session.")
        cb(false)
        return
    end

    local level_sequence, sequence_error = normalize_adventure_playlist(opts.level_sequence or self:BuildPlaylist())
    if level_sequence == nil then
        print("[Adventure Mode] Invalid level_sequence: " .. tostring(sequence_error) .. ".")
        cb(false)
        return
    end
    opts.level_sequence = level_sequence

    local initial_chapter = opts.chapter or 1
    if type(initial_chapter) ~= "number" then
        print("[Adventure Mode] Invalid initial chapter " .. tostring(initial_chapter) .. ".")
        cb(false)
        return
    end
    initial_chapter = math.floor(initial_chapter)
    if initial_chapter < 1 or initial_chapter > #level_sequence then
        print("[Adventure Mode] Initial chapter " .. tostring(initial_chapter) .. " is outside the playlist.")
        cb(false)
        return
    end
    opts.chapter = initial_chapter

    local first_preset = ShardWorldIndex:GetLevelForShard(level_sequence[initial_chapter], worldindex:GetIndexShard())
    local previous_state = get_adventure_state(index)
    local main_player_sessions = opts.player_sessions or ShardWorldIndex:CollectPlayerSessions()
    local state =
    {
        active = true,
        kind = "adventure",
        file_id = ADVENTURE_WORLD_SWITCH_FILE_ID,
        topology_key = "adventure_state",
        reason = "begin",
        sequence_id = opts.sequence_id or "default",
        slot = index:GetSlot(),
        shard = worldindex:GetIndexShard(),
        started_at = os.time(),
        updated_at = os.time(),

        level_sequence = ShardWorldIndex:DeepCopy(level_sequence),
        chapter = initial_chapter,
        current_preset = first_preset,
        current_session_id = nil,
        player_sessions = ShardWorldIndex:GetCharacterOnlySessions(main_player_sessions),
        participants = ShardWorldIndex:SessionsToUseridMap(main_player_sessions),
        late_joiners = {},
        adventure_player_sessions = {},
        first_chapter_start_inv_pending = initial_chapter == 1,
        first_chapter_start_inv_given = {},
        maxwell_intro_played_chapters = {},
        maxwell_throne_puppet = get_maxwell_throne_puppet_record(previous_state ~= nil and previous_state.maxwell_throne_puppet or nil),
    }

    worldindex:BeginWorldSwitch({
        kind = "adventure",
        reason = "begin",
        sequence_id = state.sequence_id,
        target = { type = "generated", level = first_preset, world_type = "adventure", cleanup_on_return = true },
        file_id = ADVENTURE_WORLD_SWITCH_FILE_ID,
        reuse_existing = false,
        level_sequence = level_sequence,
        chapter = initial_chapter,
        keep_session = true,
        player_sessions = main_player_sessions,
        fallback_player_sessions = false,
        return_position = opts.return_position,
        state = state,
    }, function(success)
        if success then
            set_adventure_state(index, worldindex:GetState(ADVENTURE_WORLD_SWITCH_FILE_ID))
        end
        cb(success)
    end)
end

function ShardAdventureIndex:BeginSecondary(opts, cb)
    local index = self.index
    local worldindex = index.worldindex
    cb = cb or NOOP
    opts = opts or {}

    if self:IsActive() then
        print("[Adventure Mode] Secondary adventure already active.")
        cb(false)
        return
    end

    local home_session = index:GetSession()
    if home_session == nil or home_session == "" then
        print("[Adventure Mode] Cannot begin secondary adventure without a home shard session.")
        cb(false)
        return
    end

    local level_sequence, sequence_error = normalize_adventure_playlist(opts.level_sequence)
    if level_sequence == nil then
        print("[Adventure Mode] Invalid secondary level_sequence: " .. tostring(sequence_error) .. ".")
        cb(false)
        return
    end
    opts.level_sequence = level_sequence

    local initial_chapter = opts.chapter or 1
    if type(initial_chapter) ~= "number" then
        print("[Adventure Mode] Invalid secondary initial chapter " .. tostring(initial_chapter) .. ".")
        cb(false)
        return
    end
    initial_chapter = math.floor(initial_chapter)
    if initial_chapter < 1 or initial_chapter > #level_sequence then
        print("[Adventure Mode] Secondary initial chapter " .. tostring(initial_chapter) .. " is outside the playlist.")
        cb(false)
        return
    end
    opts.chapter = initial_chapter

    local first_preset = ShardWorldIndex:GetLevelForShard(level_sequence[initial_chapter], worldindex:GetIndexShard())
    local state =
    {
        active = true,
        kind = "adventure",
        file_id = ADVENTURE_WORLD_SWITCH_FILE_ID,
        topology_key = "adventure_state",
        secondary = true,
        reason = "begin",
        sequence_id = opts.sequence_id or "default",
        slot = index:GetSlot(),
        shard = worldindex:GetIndexShard(),
        started_at = os.time(),
        updated_at = os.time(),

        level_sequence = ShardWorldIndex:DeepCopy(level_sequence),
        chapter = initial_chapter,
        current_preset = first_preset,
        current_session_id = nil,
        player_sessions = nil,
        adventure_player_sessions = {},
        first_chapter_start_inv_pending = false,
        first_chapter_start_inv_given = {},
        maxwell_intro_played_chapters = {},
    }

    worldindex:BeginWorldSwitch({
        kind = "adventure",
        reason = "begin",
        sequence_id = state.sequence_id,
        target = { type = "generated", level = first_preset, world_type = "adventure", cleanup_on_return = true },
        file_id = ADVENTURE_WORLD_SWITCH_FILE_ID,
        reuse_existing = false,
        level_sequence = level_sequence,
        chapter = initial_chapter,
        keep_session = true,
        state = state,
    }, function(success)
        if success then
            set_adventure_state(index, worldindex:GetState(ADVENTURE_WORLD_SWITCH_FILE_ID))
        end
        cb(success)
    end)
end

-- Advance to the next chapter in the sequence, generating a fresh world. If the
-- current chapter is the last one, return to the main world instead.
function ShardAdventureIndex:Advance(opts, cb)
    local index = self.index
    local worldindex = index.worldindex
    if type(opts) == "function" and cb == nil then
        cb = opts
        opts = nil
    end
    cb = cb or NOOP
    opts = opts or {}

    local state = get_adventure_state(index)
    if state == nil or not state.active or state.main == nil then
        print("[Adventure Mode] No active adventure to advance.")
        cb(false)
        return
    end

    local current_chapter = state.chapter or 1
    local next_chapter = opts.chapter or (current_chapter + 1)
    if type(next_chapter) ~= "number" then
        next_chapter = current_chapter + 1
    end
    next_chapter = math.floor(next_chapter)
    if next_chapter <= current_chapter then
        print("[Adventure Mode] Cannot advance to chapter "..tostring(next_chapter).." from chapter "..tostring(current_chapter)..".")
        cb(false)
        return
    end
    if next_chapter > #state.level_sequence then
        return self:ReturnToMainWorld("complete", cb)
    end

    local next_preset = ShardWorldIndex:GetLevelForShard(state.level_sequence[next_chapter], worldindex:GetIndexShard())
    local player_sessions = opts.player_sessions or ShardWorldIndex:CollectPlayerSessions()
    local next_player_sessions = ShardWorldIndex:MergeSessionLists(player_sessions, state.adventure_player_sessions)
    local pending_generation =
    {
        reason = "advance",
        chapter = next_chapter,
        current_preset = next_preset,
        player_sessions = next_player_sessions,
        adventure_player_sessions = ShardWorldIndex:DeepCopy(next_player_sessions) or {},
        first_chapter_start_inv_pending = false,
        cleanup_session_id = state.current_session_id,
        file_id = ADVENTURE_WORLD_SWITCH_FILE_ID,
    }

    worldindex:QueueNextWorld({
        target = { type = "generated", level = next_preset, world_type = "adventure", cleanup_on_return = true },
        file_id = ADVENTURE_WORLD_SWITCH_FILE_ID,
        reuse_existing = false,
        chapter = next_chapter,
        keep_session = true,
        pending_generation = pending_generation,
    }, function(success, chapter)
        if success then
            set_adventure_state(index, worldindex:GetState(ADVENTURE_WORLD_SWITCH_FILE_ID))
        end
        cb(success, chapter)
    end)
end

function ShardAdventureIndex:AdvanceSecondary(opts, cb)
    local index = self.index
    local worldindex = index.worldindex
    if type(opts) == "function" and cb == nil then
        cb = opts
        opts = nil
    end
    cb = cb or NOOP
    opts = opts or {}

    local state = get_adventure_state(index)
    if state == nil or not state.active or state.main == nil then
        print("[Adventure Mode] No active secondary adventure to advance.")
        cb(false)
        return
    end

    local next_chapter = opts.chapter or ((state.chapter or 1) + 1)
    if next_chapter > #state.level_sequence then
        return self:ReturnToMainWorld("complete", cb)
    end

    local next_preset = ShardWorldIndex:GetLevelForShard(state.level_sequence[next_chapter], worldindex:GetIndexShard())
    local pending_generation =
    {
        reason = "advance",
        chapter = next_chapter,
        current_preset = next_preset,
        player_sessions = nil,
        adventure_player_sessions = nil,
        first_chapter_start_inv_pending = false,
        cleanup_session_id = state.current_session_id,
        file_id = ADVENTURE_WORLD_SWITCH_FILE_ID,
    }

    worldindex:QueueNextWorld({
        target = { type = "generated", level = next_preset, world_type = "adventure", cleanup_on_return = true },
        file_id = ADVENTURE_WORLD_SWITCH_FILE_ID,
        reuse_existing = false,
        chapter = next_chapter,
        keep_session = true,
        pending_generation = pending_generation,
    }, function(success, chapter)
        if success then
            set_adventure_state(index, worldindex:GetState(ADVENTURE_WORLD_SWITCH_FILE_ID))
        end
        cb(success, chapter)
    end)
end

function ShardAdventureIndex:Complete(cb)
    return self:Advance(cb)
end

function ShardAdventureIndex:ReturnToMainWorld(reason, cb)
    local index = self.index
    local worldindex = index.worldindex
    cb = cb or NOOP

    local state = get_adventure_state(index)
    if state == nil or not state.active or state.main == nil then
        print("[Adventure Mode] No active adventure to return from.")
        cb(false)
        return
    end

    inject_late_joiners_into_main_world(index, state, function()
        worldindex:ReturnToStoredWorld(reason or "return", function(success)
            if success then
                worldindex:RestoreParentWorldSwitch(state, function()
                    set_adventure_state(index, worldindex:GetState(ADVENTURE_WORLD_SWITCH_FILE_ID))
                    cb(success)
                end)
                return
            end
            cb(success)
        end, state.main.player_sessions)
    end)
end

function ShardAdventureIndex:Start(opts)
    local index = self.index
    if index == nil then
        return false
    end
    if TheShard ~= nil and not ShardWorldIndex:IsMasterShard() then
        print("[Adventure Mode] ShardGameIndex.adventure:Start must be called on the master shard.")
        return false
    end
    opts = opts or {}
    local level_sequence, sequence_error = normalize_adventure_playlist(opts.level_sequence or self:BuildPlaylist())
    if level_sequence == nil then
        print("[Adventure Mode] Cannot start adventure: " .. tostring(sequence_error) .. ".")
        return false
    end
    opts.level_sequence = level_sequence

    local initial_chapter = opts.chapter or 1
    if type(initial_chapter) ~= "number" then
        print("[Adventure Mode] Cannot start at chapter " .. tostring(initial_chapter) .. ".")
        return false
    end
    initial_chapter = math.floor(initial_chapter)
    if initial_chapter < 1 or initial_chapter > #level_sequence then
        print("[Adventure Mode] Cannot start at chapter " .. tostring(initial_chapter) .. ".")
        return false
    end
    opts.chapter = initial_chapter

    local function begin_after_save()
        self:Begin(opts, function(success)
            if success then
                send_secondary_adventure_rpc("BeginSecondaryAdventure", opts)
                restart_current_slot_after_shard_rpc(index, { adventure_transition = "begin" })
            end
        end)
    end

    if TheWorld ~= nil and TheWorld.ismastersim then
        send_force_players_to_master_rpc()
        self:WaitForSecondaryShardPlayersEmpty(function()
            index:SaveCurrent(begin_after_save)
        end, opts ~= nil and opts.secondary_shard_wait_timeout or nil, opts ~= nil and opts.secondary_shard_wait_poll_interval or nil)
    else
        ShardWorldIndex:SavePlayers()
        begin_after_save()
    end
    return true
end

function ShardAdventureIndex:AdvanceShard(opts)
    local index = self.index
    if index == nil or not self:IsActive() then
        return false
    end
    if TheShard ~= nil and not ShardWorldIndex:IsMasterShard() then
        print("[Adventure Mode] ShardGameIndex.adventure:AdvanceShard must be called on the master shard.")
        return false
    end

    opts = opts or {}

    local function advance_after_save()
        self:Advance(opts, function(success, next_chapter)
            if success then
                if next_chapter ~= nil then
                    send_secondary_adventure_rpc("AdvanceSecondaryAdventure", { chapter = next_chapter })
                    restart_current_slot_after_shard_rpc(index, { adventure_transition = "advance" })
                else
                    send_secondary_adventure_rpc("ReturnSecondaryAdventure", { reason = "complete" })
                    restart_current_slot_after_shard_rpc(index, { adventure_transition = "complete" })
                end
            end
        end)
    end

    if TheWorld ~= nil and TheWorld.ismastersim then
        if ShardWorldIndex:GetSecondaryShardPlayerCount() > 0 then
            print("[Adventure Mode] Cannot advance while players are on secondary shards.")
            return false
        end

        self:WaitForSecondaryShardPlayersEmpty(function()
            ShardWorldIndex:SavePlayers()
            advance_after_save()
        end, opts.secondary_shard_wait_timeout or nil, opts.secondary_shard_wait_poll_interval or nil)
    else
        ShardWorldIndex:SavePlayers()
        advance_after_save()
    end
    return true
end

function ShardAdventureIndex:CompleteShard(opts)
    return self:AdvanceShard(opts)
end

function ShardAdventureIndex:ReturnFromShard(reason)
    local index = self.index
    if index == nil or not self:IsActive() then
        return false
    end
    if TheShard ~= nil and not ShardWorldIndex:IsMasterShard() then
        send_master_adventure_rpc("ReturnFromAdventure", { reason = reason or "return" })
        return true
    end

    local function return_after_save()
        ShardWorldIndex:SavePlayers()
        self:ReturnToMainWorld(reason or "return", function(success)
            if success then
                send_secondary_adventure_rpc("ReturnSecondaryAdventure", { reason = reason or "return" })
                restart_current_slot_after_shard_rpc(index, { adventure_transition = reason or "return" })
            end
        end)
    end

    if TheWorld ~= nil and TheWorld.ismastersim then
        send_force_players_to_master_rpc()
        self:WaitForSecondaryShardPlayersEmpty(return_after_save)
    else
        return_after_save()
    end
    return true
end
