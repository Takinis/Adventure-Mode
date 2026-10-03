-- Adventure run manager for ShardIndex.
-- Persistent run data and transition orchestration live in ShardWorldIndex;
-- this class owns chapter rules, adventure player sessions, and shard handlers.

GLOBAL.setfenv(1, GLOBAL)

local ShardWorldIndex = ShardWorldIndex

ShardAdventureIndex = Class(function(self, index)
    self.index = index
    self._return_pending = false
    self._return_callbacks = nil
    self._advance_pending = false
    self._reset_pending = false
    self._reset_callbacks = nil
    self._forwarded_reset_request_id = nil
    self._forwarded_reset_timeout_task = nil
    self._forwarded_return_request_id = nil
    self._forwarded_return_timeout_task = nil
    self._synchronize_pending = false
    self._run_id_migration_pending = false
end)

local ADVENTURE_WORLD_INDEX_FILE_ID = "adventure"
local ADVENTURE_SECONDARY_LEVEL = "ADVENTURE_SECONDARY"
local ADVENTURE_DARKNESS_LEVEL = "DARKNESS"
local ADVENTURE_ENDING_LEVEL = "ENDING"
local ADVENTURE_LEVEL_COUNT = 4
local ADVENTURE_STATE_VERSION = 2
local PUPPET_SYMBOLS = { "foot", "leg" }
local FORWARDED_RESET_TIMEOUT = 150
local FORWARDED_RETURN_TIMEOUT = 150
local adventure_run_serial = 0
local adventure_reset_request_serial = 0
local adventure_return_request_serial = 0

ShardWorldIndex:RegisterWorldIndexFileID(ADVENTURE_WORLD_INDEX_FILE_ID)

local function get_secondary_adventure_level()
    return ADVENTURE_SECONDARY_LEVEL
end

local function build_secondary_adventure_target()
    return
    {
        id = ADVENTURE_SECONDARY_LEVEL,
        secondary = ADVENTURE_SECONDARY_LEVEL,
    }
end

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

local function get_adventure_chapter_revision(value, default)
    value = tonumber(value)
    value = value ~= nil and math.floor(value) or default
    return math.max(value or 1, 1)
end

local function get_next_adventure_chapter_revision(run, value)
    local current = get_adventure_chapter_revision(run ~= nil and run.chapter_revision or nil, 1)
    if value == nil then
        return current + 1
    end

    value = math.floor(tonumber(value) or 0)
    return value > current and value or nil
end

local function get_adventure_run_id(value)
    return type(value) == "string" and value ~= "" and value or nil
end

local function create_adventure_run_id(index)
    adventure_run_serial = adventure_run_serial + 1
    local session_id = index ~= nil and index:GetSession() or "session"
    local realtime = type(GetTimeReal) == "function" and tonumber(GetTimeReal()) or 0
    realtime = math.floor(realtime or 0)
    return table.concat({ tostring(session_id), tostring(os.time()), tostring(realtime), tostring(adventure_run_serial) }, ":")
end

local function create_adventure_reset_request_id(index)
    adventure_reset_request_serial = adventure_reset_request_serial + 1
    local shard_id = TheShard ~= nil and TheShard.GetShardId ~= nil and TheShard:GetShardId() or
        index ~= nil and index.GetShard ~= nil and index:GetShard() or "shard"
    return table.concat({ tostring(shard_id), tostring(os.time()), tostring(adventure_reset_request_serial) }, ":")
end

local function create_adventure_return_request_id(index)
    adventure_return_request_serial = adventure_return_request_serial + 1
    local shard_id = TheShard ~= nil and TheShard.GetShardId ~= nil and TheShard:GetShardId() or
        index ~= nil and index.GetShard ~= nil and index:GetShard() or "shard"
    return table.concat({ tostring(shard_id), tostring(os.time()), tostring(adventure_return_request_serial) }, ":")
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
    local regular_levels = {}
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
            table.insert(regular_levels, playlist_level)
        end
    end

    if not has_darkness or not has_ending then
        local missing = not has_darkness and ADVENTURE_DARKNESS_LEVEL or ADVENTURE_ENDING_LEVEL
        return nil, "missing terminal adventure level " .. missing
    end

    local ordered_regular_levels = order_adventure_playlist_levels(regular_levels)
    local playlist = {}
    for i = 1, math.min(ADVENTURE_LEVEL_COUNT, #ordered_regular_levels) do
        table.insert(playlist, ordered_regular_levels[i])
    end

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
        if get_adventure_playlist_level_id(level) == nil then
            return nil, "invalid level id at position " .. tostring(i)
        end

        table.insert(normalized, level)
    end

    return normalized
end

local function NOOP()
    ShardWorldIndex:Noop()
end

local function read_sidecar(index, cb)
    cb = cb or NOOP
    index.worldindex:ReadSidecar(cb, ADVENTURE_WORLD_INDEX_FILE_ID)
end

local function write_sidecar(index, data, cb)
    cb = cb or NOOP
    index.worldindex:WriteSidecar(data, cb, ADVENTURE_WORLD_INDEX_FILE_ID)
end

local pending_adventure_saves = setmetatable({}, { __mode = "k" })
local ADVENTURE_SAVE_RETRY_LIMIT = 3

local function queue_sidecar_save(index, run)
    if index == nil or run == nil then
        return
    end

    local pending = pending_adventure_saves[index]
    if pending == nil then
        pending = { running = false, dirty = false, retries = 0 }
        pending_adventure_saves[index] = pending
    end
    pending.run = run
    pending.dirty = true
    if pending.running then
        return
    end

    local function save_latest()
        if index.worldindex:GetState(ADVENTURE_WORLD_INDEX_FILE_ID) ~= pending.run then
            pending_adventure_saves[index] = nil
            return
        end
        pending.running = true
        pending.dirty = false
        write_sidecar(index, pending.run, function(success)
            pending.running = false
            if success then
                pending.retries = 0
            else
                pending.retries = pending.retries + 1
                pending.dirty = true
                print("[Adventure Mode] Failed to save adventure state.")
            end

            if not pending.dirty then
                pending_adventure_saves[index] = nil
                return
            end
            if pending.retries >= ADVENTURE_SAVE_RETRY_LIMIT then
                print("[Adventure Mode] Adventure state save retry limit reached.")
                pending_adventure_saves[index] = nil
                return
            end
            if TheWorld ~= nil then
                TheWorld:DoStaticTaskInTime(1, save_latest)
            else
                save_latest()
            end
        end)
    end
    save_latest()
end

local function ensure_adventure_run_id(index, run)
    local changed = false
    if run ~= nil and run.active == true and get_adventure_run_id(run.run_id) == nil and
        ShardWorldIndex:IsMasterShard() and (TheNet == nil or TheNet:GetIsMasterSimulation()) then
        run.run_id = create_adventure_run_id(index)
        run.updated_at = os.time()
        changed = true
    end
    return run, changed
end

local player_starting_inventory = {}

local function inject_late_joiners_into_main_world(index, run, cb)
    cb = cb or NOOP

    if run == nil or run.secondary or run.main == nil or run.main.session_id == nil or not TheNet:GetIsServer() then
        cb(true)
        return
    end

    local late_joiners = run.late_joiners
    if late_joiners == nil or next(late_joiners) == nil then
        cb(true)
        return
    end

    local sessions_by_userid = ShardWorldIndex:SessionListToMap(run.adventure_player_sessions)
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
        cb(true)
        return
    end

    index.worldindex:InjectPlayerSessionsIntoExistingWorld(
        run.main.session_id,
        ShardWorldIndex:GetCharacterOnlySessions(sessions),
        function(success, migrated_sessions)
            if not success then
                cb(false)
                return
            end
            run.main.player_sessions = ShardWorldIndex:MergeSessionLists(
                migrated_sessions,
                run.main.player_sessions
            )
            write_sidecar(index, run, cb)
        end
    )
end

local function cache_adventure_player_session(index, inst, mark_late_joiner)
    if TheWorld == nil or not TheWorld.ismastersim or index == nil or inst == nil or inst.userid == nil or inst.userid == "" then
        return
    end

    local run = index.worldindex:GetState(ADVENTURE_WORLD_INDEX_FILE_ID)
    if run == nil or not run.active or run.secondary then
        return
    end

    if mark_late_joiner and (run.participants == nil or not run.participants[inst.userid]) then
        run.late_joiners = run.late_joiners or {}
        run.late_joiners[inst.userid] = true
    end

    local session = ShardWorldIndex:GetPlayerSaveSession(inst)
    if session == nil then
        return
    end

    run.adventure_player_sessions = run.adventure_player_sessions or {}
    local replaced = false
    for i, existing in ipairs(run.adventure_player_sessions) do
        if existing.userid == inst.userid then
            run.adventure_player_sessions[i] = session
            replaced = true
            break
        end
    end
    if not replaced then
        table.insert(run.adventure_player_sessions, session)
    end

    run.updated_at = os.time()
    queue_sidecar_save(index, run)
end

local function send_master_adventure_rpc(name, data)
    ShardWorldIndex:SendRPCToMasterShard("AdventureMode", name, data)
end

local function give_adventure_first_chapter_start_inv(index, inst)
    if TheWorld == nil or not TheWorld.ismastersim or index == nil then
        return
    end

    local run = index.worldindex:GetState(ADVENTURE_WORLD_INDEX_FILE_ID)
    if run == nil or
        not run.active or
        run.chapter ~= 1 or
        not run.first_chapter_start_inv_pending or
        inst == nil or
        inst.userid == nil or
        inst.userid == "" then
        return
    end

    if run.participants == nil or not run.participants[inst.userid] then
        return
    end

    run.first_chapter_start_inv_given = run.first_chapter_start_inv_given or {}
    if run.first_chapter_start_inv_given[inst.userid] then
        return
    end

    run.first_chapter_start_inv_given[inst.userid] = true
    run.updated_at = os.time()
    write_sidecar(index, run, function(saved)
        if not saved then
            run.first_chapter_start_inv_given[inst.userid] = nil
            print("[Adventure Mode] Failed to persist first chapter starting inventory state.")
            return
        end
        if not inst:IsValid() then
            run.first_chapter_start_inv_given[inst.userid] = nil
            queue_sidecar_save(index, run)
            return
        end

        local items = player_starting_inventory[inst.prefab]
        if items ~= nil and #items > 0 and inst.components.inventory ~= nil then
            require("prefabs/player_common_extensions").GivePlayerStartingItems(inst, items, nil)
        end
    end)
end

local function on_adventure_player_activated(index, inst)
    cache_adventure_player_session(index, inst, true)
    give_adventure_first_chapter_start_inv(index, inst)
end

local function on_adventure_player_deactivated(index, inst)
    cache_adventure_player_session(index, inst, false)
end

local function restart_current_slot_after_shard_rpc(index, extra_params)
    extra_params = extra_params or {}
    if extra_params.adventure_transition ~= nil then
        extra_params.world_index_transition = extra_params.world_index_transition or extra_params.adventure_transition
        extra_params.world_index_file_id = ADVENTURE_WORLD_INDEX_FILE_ID
    end
    index.worldindex:RestartCurrentSlotAfterShardRPC(extra_params)
end

local function apply_adventure_world_index_options(run)
    if run == nil then
        return false
    end

    local changed = false
    local values =
    {
        managed_externally = true,
        adventure_state_version = ADVENTURE_STATE_VERSION,
        allow_unknown_world_type = true,
        allow_current_world_target = true,
        track_player_positions = false,
        collected_player_sessions_field = "adventure_player_sessions",
    }
    for key, value in pairs(values) do
        if run[key] ~= value then
            run[key] = value
            changed = true
        end
    end
    return changed
end

local function begin_adventure_world_index(index, opts, cb)
    local worldindex = index.worldindex
    local active_state = worldindex:GetState()
    if active_state == nil or active_state.active ~= true then
        worldindex:BeginWorldIndex(opts, cb)
        return
    end

    worldindex:SuspendActiveWorldIndex("adventure_begin", function(parent_state, suspended)
        if not suspended then
            cb(false)
            return
        end

        opts.state = ShardWorldIndex:DeepCopy(opts.state) or {}
        opts.state.parent_world_index_state = ShardWorldIndex:DeepCopy(parent_state)
        worldindex:BeginWorldIndex(opts, function(success)
            if success then
                cb(true)
                return
            end
            worldindex:ResumeSuspendedWorldIndex(parent_state, function()
                cb(false)
            end)
        end)
    end)
end

local function has_current_adventure_maxwell_intro_played(run)
    local chapter = run ~= nil and run.chapter or nil
    local played_chapters = run ~= nil and run.maxwell_intro_played_chapters or nil
    local played = type(played_chapters) == "table" and played_chapters[chapter] or nil
    return run ~= nil and
        run.active == true and
        chapter ~= nil and
        (played == true or type(played) == "table" and next(played) ~= nil)
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

    local skins = record.skins
    if type(skins) == "table" then
        skins =
        {
            base = type(skins.base) == "string" and skins.base or "",
            body = type(skins.body) == "string" and skins.body or "",
            hand = type(skins.hand) == "string" and skins.hand or "",
            legs = type(skins.legs) == "string" and skins.legs or "",
            feet = type(skins.feet) == "string" and skins.feet or "",
            mode = type(skins.mode) == "string" and skins.mode or "",
            monkey_curse = type(skins.monkey_curse) == "string" and skins.monkey_curse or "",
        }
        if skins.base == "" and
            skins.body == "" and
            skins.hand == "" and
            skins.legs == "" and
            skins.feet == "" and
            skins.mode == "" and
            skins.monkey_curse == "" then
            skins = nil
        else
            skins.mode = skins.mode ~= "" and skins.mode or "normal_skin"
        end
    else
        skins = nil
    end

    local symbols = {}
    for _, target in ipairs(PUPPET_SYMBOLS) do
        local data = type(record.symbols) == "table" and record.symbols[target] or nil
        if type(data) == "table" and type(data.build) == "number" and type(data.symbol) == "number" then
            symbols[target] =
            {
                build = data.build,
                symbol = data.symbol,
                skin = data.skin == true,
            }
        end
    end
    symbols = next(symbols) ~= nil and symbols or nil

    return
    {
        character = character,
        build = build,
        userid = type(record.userid) == "string" and record.userid or nil,
        skins = skins,
        symbols = symbols,
    }
end

local function get_adventure_maxwell_throne_puppet(index)
    local run = index.worldindex:GetState(ADVENTURE_WORLD_INDEX_FILE_ID)
    return run ~= nil and get_maxwell_throne_puppet_record(run.maxwell_throne_puppet) or nil
end

local function set_adventure_maxwell_throne_puppet(index, record)
    local run = index.worldindex:GetState(ADVENTURE_WORLD_INDEX_FILE_ID)
    if run == nil then
        return false
    end

    local puppet = get_maxwell_throne_puppet_record(record)
    if puppet == nil then
        return false
    end

    run.maxwell_throne_puppet = puppet
    run.updated_at = os.time()
    queue_sidecar_save(index, run)
    return true
end

local function mark_current_adventure_maxwell_intro_played(index)
    local run = index.worldindex:GetState(ADVENTURE_WORLD_INDEX_FILE_ID)
    local chapter = run ~= nil and run.chapter or nil
    if run == nil or not run.active or chapter == nil then
        return false
    end

    run.maxwell_intro_played_chapters = run.maxwell_intro_played_chapters or {}
    if run.maxwell_intro_played_chapters[chapter] == true then
        return true
    end

    run.maxwell_intro_played_chapters[chapter] = true
    run.updated_at = os.time()
    queue_sidecar_save(index, run)
    return true
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

function ShardAdventureIndex:RememberStartingInventory(inst)
    if inst ~= nil and inst.prefab ~= nil and inst.starting_inventory ~= nil then
        player_starting_inventory[inst.prefab] = ShardWorldIndex:DeepCopy(inst.starting_inventory)
    end
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
    local run = self.index.worldindex:GetState(ADVENTURE_WORLD_INDEX_FILE_ID)
    return run ~= nil and run.active == true
end

function ShardAdventureIndex:GetState()
    return self.index.worldindex:GetState(ADVENTURE_WORLD_INDEX_FILE_ID)
end

function ShardAdventureIndex:EnsureRunID()
    local run, changed = ensure_adventure_run_id(self.index, self:GetState())
    self._run_id_migration_pending = self._run_id_migration_pending or changed
    return run
end

function ShardAdventureIndex:MigrateLoadedState(cb)
    cb = cb or NOOP
    local function migrate()
        local run, changed = ensure_adventure_run_id(self.index, self:GetState())
        changed = apply_adventure_world_index_options(run) or changed
        self._run_id_migration_pending = self._run_id_migration_pending or changed
        if run == nil or not self._run_id_migration_pending then
            cb(true)
            return
        end

        write_sidecar(self.index, run, function(success)
            if success then
                self._run_id_migration_pending = false
            else
                print("[Adventure Mode] Failed to persist the migrated adventure state.")
            end
            cb(success == true)
        end)
    end

    local run = self:GetState()
    if run ~= nil and run.active ~= true and
        type(run.return_pending) == "table" then
        self.index.worldindex:RestoreParentWorldIndex(run, function(success)
            if success then
                migrate()
            else
                print("[Adventure Mode] Failed to restore the parent world index.")
                cb(false)
            end
        end)
        return
    end

    migrate()
end

function ShardAdventureIndex:GetSecondarySyncData()
    local run = self:EnsureRunID()
    if run == nil or not run.active then
        return { active = false }
    end
    return
    {
        active = true,
        run_id = run.run_id,
        chapter = run.chapter,
        chapter_revision = get_adventure_chapter_revision(run.chapter_revision, 1),
        sequence_id = run.sequence_id,
        level_sequence = ShardWorldIndex:DeepCopy(run.level_sequence),
    }
end

function ShardAdventureIndex:SynchronizeSecondary(data, cb, continuing)
    cb = cb or NOOP
    if not continuing then
        if self._synchronize_pending then
            cb(false, false)
            return false
        end

        self._synchronize_pending = true
        local completed = false
        local on_complete = cb
        cb = function(...)
            if completed then
                return
            end
            completed = true
            self._synchronize_pending = false
            on_complete(...)
        end
    end

    data = type(data) == "table" and data or {}
    local index = self.index

    local function get_running_session_id()
        return TheWorld ~= nil and TheWorld.meta ~= nil and
            TheWorld.meta.session_identifier or nil
    end

    local function needs_restart_for_state(run)
        if type(run) ~= "table" then
            return false
        end

        local running_session_id = get_running_session_id()
        if run.active == true then
            return type(run.pending_generation) == "table" or
                run.current_session_id == nil or run.current_session_id == "" or
                running_session_id ~= nil and running_session_id ~= "" and
                    run.current_session_id ~= running_session_id
        end

        local home = run.home or run.main
        local home_session_id = home ~= nil and home.session_id or nil
        return home_session_id ~= nil and home_session_id ~= "" and
            running_session_id ~= nil and running_session_id ~= "" and
            home_session_id ~= running_session_id
    end

    local function clear_completed_transaction(run, done)
        local transaction = run ~= nil and run.secondary_transition or nil
        if type(transaction) == "table" then
            if type(transaction.request_id) ~= "string" or transaction.request_id == "" then
                done(false, false, nil)
                return
            end

            if transaction.status == "committed" then
                local restart_required = needs_restart_for_state(run)
                index.worldindex:FinalizeSecondaryTransition(
                    transaction.request_id,
                    transaction.file_id or ADVENTURE_WORLD_INDEX_FILE_ID,
                    function(finalized)
                        local retry_required = finalized ~= true
                        done(
                            finalized == true,
                            restart_required or retry_required,
                            retry_required and transaction.request_id or nil
                        )
                    end
                )
            else
                local original_index = type(transaction.original_index) == "table" and
                    transaction.original_index or nil
                local original_session_id = original_index ~= nil and original_index.session_id or nil
                local running_session_id = get_running_session_id()
                local restart_required = original_session_id ~= nil and original_session_id ~= "" and
                    running_session_id ~= nil and running_session_id ~= "" and
                    original_session_id ~= running_session_id
                index.worldindex:AbortPreparedSecondaryTransition(
                    transaction.request_id,
                    transaction.file_id or ADVENTURE_WORLD_INDEX_FILE_ID,
                    function(restored)
                        local retry_required = restored ~= true
                        done(
                            restored == true,
                            restart_required or retry_required,
                            retry_required and transaction.request_id or nil
                        )
                    end
                )
            end
            return
        end

        local cleanup_session_id = run ~= nil and run.deferred_cleanup_session_id or nil
        if run == nil or (run.secondary_transition == nil and cleanup_session_id == nil) then
            done(true, false, nil)
            return
        end

        run.secondary_transition = nil
        run.deferred_cleanup_session_id = nil
        write_sidecar(index, run, function(saved)
            if saved and cleanup_session_id ~= nil and cleanup_session_id ~= "" and run.main ~= nil then
                ShardWorldIndex:DeleteSessionIfNotHome(cleanup_session_id, run.main.session_id)
            end
            done(saved == true, false, nil)
        end)
    end

    read_sidecar(index, function(run, read_success)
        if read_success == false then
            cb(false, false)
            return
        end
        if run ~= nil and type(run.secondary_transition) == "table" then
            clear_completed_transaction(run, function(success, restart_required, retry_id)
                if not success or restart_required then
                    cb(success, restart_required, retry_id)
                else
                    self:SynchronizeSecondary(data, cb, true)
                end
            end)
            return
        end

        local is_active = run ~= nil and run.active == true

        if data.active ~= true then
            if not is_active then
                clear_completed_transaction(run, function(success, restart_required, retry_id)
                    cb(success, restart_required or success and needs_restart_for_state(run), retry_id)
                end)
                return
            end
            self:ReturnToMainWorld("resync", function(success)
                cb(success == true, success == true)
            end)
            return
        end

        local level_sequence, sequence_error = normalize_adventure_playlist(data.level_sequence)
        local chapter = math.floor(tonumber(data.chapter) or 0)
        local chapter_revision = math.floor(tonumber(data.chapter_revision) or 1)
        if level_sequence == nil or chapter < 1 or chapter > #level_sequence or chapter_revision < 1 then
            print("[Adventure Mode] Cannot synchronize secondary adventure: "..tostring(sequence_error or "invalid chapter")..".")
            cb(false, false)
            return
        end

        local run_id = get_adventure_run_id(run ~= nil and run.run_id or nil)
        local synced_run_id = get_adventure_run_id(data.run_id)
        -- One-sided run IDs identify a stale pre-run-id shard, even when chapter counters match.
        local same_run = (synced_run_id ~= nil and run_id == synced_run_id) or
            (synced_run_id == nil and run_id == nil)
        if is_active and same_run and
            run.sequence_id == (data.sequence_id or "default") and
            run.chapter == chapter and
            get_adventure_chapter_revision(run.chapter_revision, 1) == chapter_revision then
            clear_completed_transaction(run, function(success, restart_required, retry_id)
                cb(success, restart_required or success and needs_restart_for_state(run), retry_id)
            end)
            return
        end

        local opts =
        {
            level_sequence = level_sequence,
            chapter = chapter,
            chapter_revision = chapter_revision,
            sequence_id = data.sequence_id,
            run_id = synced_run_id,
        }
        local function begin()
            self:BeginSecondary(opts, function(success)
                cb(success == true, success == true)
            end)
        end

        if is_active then
            self:ReturnToMainWorld("resync", function(success)
                if success then
                    begin()
                else
                    cb(false, false)
                end
            end)
        else
            begin()
        end
    end)
    return true
end

function ShardAdventureIndex:IsSynchronizingSecondary()
    return self._synchronize_pending == true
end

function ShardAdventureIndex:GetMaxwellThronePuppet()
    return get_adventure_maxwell_throne_puppet(self.index)
end

function ShardAdventureIndex:SetMaxwellThronePuppet(record)
    return set_adventure_maxwell_throne_puppet(self.index, record)
end

function ShardAdventureIndex:IsCurrentMaxwellIntroPlayed()
    local run = self.index.worldindex:GetState(ADVENTURE_WORLD_INDEX_FILE_ID)
    return has_current_adventure_maxwell_intro_played(run)
end

function ShardAdventureIndex:MarkCurrentMaxwellIntroPlayed()
    return mark_current_adventure_maxwell_intro_played(self.index)
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
    opts.run_id = get_adventure_run_id(opts.run_id) or create_adventure_run_id(index)

    local first_preset = ShardWorldIndex:GetLevelForShard(level_sequence[initial_chapter], worldindex:GetIndexShard())
    local function begin_with_previous_run(previous_run)
        local main_player_sessions = opts.player_sessions or ShardWorldIndex:CollectPlayerSessions()
        local initial_player_sessions = ShardWorldIndex:GetCharacterOnlySessions(main_player_sessions)
        local run =
        {
            active = true,
            kind = "adventure",
            file_id = ADVENTURE_WORLD_INDEX_FILE_ID,
            reason = "begin",
            run_id = opts.run_id,
            sequence_id = opts.sequence_id or "default",
            slot = index:GetSlot(),
            shard = worldindex:GetIndexShard(),
            started_at = os.time(),
            updated_at = os.time(),

            level_sequence = ShardWorldIndex:DeepCopy(level_sequence),
            chapter = initial_chapter,
            chapter_revision = get_adventure_chapter_revision(opts.chapter_revision, 1),
            current_preset = first_preset,
            current_session_id = nil,
            player_sessions = initial_player_sessions,
            chapter_start_player_sessions = initial_player_sessions or {},
            participants = ShardWorldIndex:SessionsToUseridMap(main_player_sessions),
            late_joiners = {},
            adventure_player_sessions = {},
            first_chapter_start_inv_pending = initial_chapter == 1,
            first_chapter_start_inv_given = {},
            maxwell_intro_played_chapters = {},
            maxwell_throne_puppet = get_maxwell_throne_puppet_record(previous_run ~= nil and previous_run.maxwell_throne_puppet or nil),
        }
        apply_adventure_world_index_options(run)

        begin_adventure_world_index(index, {
            kind = "adventure",
            reason = "begin",
            sequence_id = run.sequence_id,
            target = { type = "generated", level = first_preset, world_type = "adventure", cleanup_on_return = true },
            file_id = ADVENTURE_WORLD_INDEX_FILE_ID,
            reuse_existing = false,
            level_sequence = level_sequence,
            chapter = initial_chapter,
            keep_session = true,
            player_sessions = main_player_sessions,
            fallback_player_sessions = false,
            return_position = opts.return_position,
            state = run,
            allow_unknown_world_type = true,
            allow_current_world_target = true,
        }, function(success)
            cb(success)
        end)
    end

    local previous_run = worldindex:GetState(ADVENTURE_WORLD_INDEX_FILE_ID)
    if previous_run ~= nil then
        begin_with_previous_run(previous_run)
    else
        read_sidecar(index, function(previous_run, read_success)
            if read_success == false then
                cb(false)
                return
            end
            begin_with_previous_run(previous_run)
        end)
    end
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

    local first_preset = get_secondary_adventure_level()
    local first_target = build_secondary_adventure_target()
    local run =
    {
        active = true,
        kind = "adventure",
        file_id = ADVENTURE_WORLD_INDEX_FILE_ID,
        secondary = true,
        reason = "begin",
        run_id = get_adventure_run_id(opts.run_id),
        sequence_id = opts.sequence_id or "default",
        slot = index:GetSlot(),
        shard = worldindex:GetIndexShard(),
        started_at = os.time(),
        updated_at = os.time(),

        level_sequence = ShardWorldIndex:DeepCopy(level_sequence),
        chapter = initial_chapter,
        chapter_revision = get_adventure_chapter_revision(opts.chapter_revision, 1),
        current_preset = first_preset,
        current_session_id = nil,
        player_sessions = nil,
        adventure_player_sessions = {},
        first_chapter_start_inv_pending = false,
        first_chapter_start_inv_given = {},
        maxwell_intro_played_chapters = {},
        secondary_transition = ShardWorldIndex:DeepCopy(opts.secondary_transition),
    }
    apply_adventure_world_index_options(run)

    begin_adventure_world_index(index, {
        kind = "adventure",
        reason = "begin",
        sequence_id = run.sequence_id,
        target = { type = "generated", level = first_target, world_type = "adventure", cleanup_on_return = true },
        file_id = ADVENTURE_WORLD_INDEX_FILE_ID,
        reuse_existing = false,
        level_sequence = level_sequence,
        chapter = initial_chapter,
        keep_session = true,
        state = run,
        allow_unknown_world_type = true,
        allow_current_world_target = true,
    }, function(success)
        cb(success)
    end)
end

local function revive_player_session(session)
    local out = ShardWorldIndex:DeepCopy(session)
    if type(out) ~= "table" or type(out.data) ~= "string" then
        return out
    end

    local success, record = RunInSandboxSafe(out.data)
    local player_data = success and type(record) == "table" and record.data or nil
    if type(player_data) ~= "table" then
        return out
    end

    local health_data = type(player_data.health) == "table" and player_data.health or nil
    local health = health_data ~= nil and tonumber(health_data.health) or nil
    local health_percent = health_data ~= nil and tonumber(health_data.percent) or nil
    local is_dead = player_data.is_ghost == true or
        health ~= nil and health <= 0 or
        health == nil and health_percent ~= nil and health_percent <= 0
    if not is_dead then
        return out
    end

    player_data.is_ghost = nil
    player_data.death_posx = nil
    player_data.death_posy = nil
    player_data.death_posz = nil
    player_data.death_shardid = nil
    player_data.health = health_data or {}
    player_data.health.health = nil
    player_data.health.percent = 1
    out.data = DataDumper(record, nil, BRANCH ~= "dev")
    return out
end

local function revive_player_sessions(sessions)
    local revived = {}
    for _, session in ipairs(sessions or {}) do
        local restored = revive_player_session(session)
        if restored ~= nil then
            table.insert(revived, restored)
        end
    end
    return #revived > 0 and revived or nil
end

local function get_current_chapter_start_player_sessions(run, opts)
    if type(opts.player_sessions) == "table" and #opts.player_sessions > 0 then
        return revive_player_sessions(opts.player_sessions)
    end

    local current = ShardWorldIndex:CollectPlayerSessions()
    local current_sessions = revive_player_sessions(
        ShardWorldIndex:MergeSessionLists(current, run.adventure_player_sessions)
    )
    local character_fallback = ShardWorldIndex:GetCharacterOnlySessions(
        ShardWorldIndex:MergeSessionLists(current_sessions, run.main ~= nil and run.main.player_sessions or nil)
    )
    local fallback_sessions = ShardWorldIndex:MergeSessionLists(current_sessions, character_fallback)
    if type(run.chapter_start_player_sessions) == "table" and #run.chapter_start_player_sessions > 0 then
        return ShardWorldIndex:MergeSessionLists(
            revive_player_sessions(run.chapter_start_player_sessions),
            fallback_sessions
        )
    end

    return fallback_sessions
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

    local run = worldindex:GetState(ADVENTURE_WORLD_INDEX_FILE_ID)
    if run == nil or not run.active or run.secondary or run.main == nil then
        print("[Adventure Mode] No active adventure to advance.")
        cb(false)
        return
    end

    local current_chapter = run.chapter or 1
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
    if next_chapter > #run.level_sequence then
        return self:ReturnToMainWorld("complete", cb)
    end

    local next_preset = ShardWorldIndex:GetLevelForShard(run.level_sequence[next_chapter], worldindex:GetIndexShard())
    local player_sessions = opts.player_sessions or ShardWorldIndex:CollectPlayerSessions()
    local next_player_sessions = ShardWorldIndex:MergeSessionLists(player_sessions, run.adventure_player_sessions)
    local next_revision = get_next_adventure_chapter_revision(run, opts.chapter_revision)
    if next_revision == nil then
        print("[Adventure Mode] Cannot advance with a stale chapter revision.")
        cb(false)
        return
    end
    local next_player_snapshot = ShardWorldIndex:DeepCopy(next_player_sessions) or {}
    local pending_generation =
    {
        reason = "advance",
        chapter = next_chapter,
        current_preset = next_preset,
        player_sessions = next_player_snapshot,
        cleanup_session_id = run.current_session_id,
        file_id = ADVENTURE_WORLD_INDEX_FILE_ID,
        state =
        {
            chapter_revision = next_revision,
            chapter_start_player_sessions = next_player_snapshot,
            adventure_player_sessions = next_player_snapshot,
            first_chapter_start_inv_pending = false,
        },
    }

    worldindex:QueueNextWorld({
        target = { type = "generated", level = next_preset, world_type = "adventure", cleanup_on_return = true },
        file_id = ADVENTURE_WORLD_INDEX_FILE_ID,
        reuse_existing = false,
        chapter = next_chapter,
        keep_session = true,
        pending_generation = pending_generation,
    }, function(success, chapter)
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

    local run = worldindex:GetState(ADVENTURE_WORLD_INDEX_FILE_ID)
    if run == nil or not run.active or not run.secondary or run.main == nil then
        print("[Adventure Mode] No active secondary adventure to advance.")
        cb(false)
        return
    end

    local next_chapter = math.floor(tonumber(opts.chapter) or ((run.chapter or 1) + 1))
    if next_chapter <= (run.chapter or 1) then
        print("[Adventure Mode] Cannot advance secondary adventure to chapter "..tostring(next_chapter)..".")
        cb(false)
        return
    end
    if next_chapter > #run.level_sequence then
        return self:ReturnToMainWorld("complete", cb)
    end

    local next_preset = get_secondary_adventure_level()
    local next_target = build_secondary_adventure_target()
    local next_revision = get_next_adventure_chapter_revision(run, opts.chapter_revision)
    if next_revision == nil then
        print("[Adventure Mode] Cannot advance secondary adventure with a stale chapter revision.")
        cb(false)
        return
    end
    local pending_generation =
    {
        reason = "advance",
        chapter = next_chapter,
        current_preset = next_preset,
        player_sessions = nil,
        cleanup_session_id = run.current_session_id,
        file_id = ADVENTURE_WORLD_INDEX_FILE_ID,
        state =
        {
            chapter_revision = next_revision,
            first_chapter_start_inv_pending = false,
        },
        clear_fields = { "adventure_player_sessions" },
    }

    worldindex:QueueNextWorld({
        target = { type = "generated", level = next_target, world_type = "adventure", cleanup_on_return = true },
        file_id = ADVENTURE_WORLD_INDEX_FILE_ID,
        reuse_existing = false,
        chapter = next_chapter,
        keep_session = true,
        pending_generation = pending_generation,
    }, function(success, chapter)
        cb(success, chapter)
    end)
end

function ShardAdventureIndex:ResetCurrentChapter(opts, cb)
    local index = self.index
    local worldindex = index.worldindex
    if type(opts) == "function" and cb == nil then
        cb = opts
        opts = nil
    end
    cb = cb or NOOP
    opts = opts or {}

    local run = worldindex:GetState(ADVENTURE_WORLD_INDEX_FILE_ID)
    if run == nil or not run.active or run.secondary or run.main == nil then
        print("[Adventure Mode] No active adventure chapter to reset.")
        cb(false)
        return
    end

    local chapter = math.floor(tonumber(opts.chapter) or tonumber(run.chapter) or 1)
    if chapter ~= run.chapter or type(run.level_sequence) ~= "table" or run.level_sequence[chapter] == nil then
        print("[Adventure Mode] Cannot reset adventure chapter "..tostring(chapter)..".")
        cb(false)
        return
    end

    local next_revision = get_next_adventure_chapter_revision(run, opts.chapter_revision)
    if next_revision == nil then
        print("[Adventure Mode] Cannot reset with a stale chapter revision.")
        cb(false)
        return
    end

    local player_sessions = get_current_chapter_start_player_sessions(run, opts)
    local preset = ShardWorldIndex:GetLevelForShard(run.level_sequence[chapter], worldindex:GetIndexShard())
    local chapter_player_snapshot = ShardWorldIndex:DeepCopy(player_sessions) or {}
    local pending_state =
    {
        chapter_revision = next_revision,
        chapter_start_player_sessions = chapter_player_snapshot,
        adventure_player_sessions = chapter_player_snapshot,
        first_chapter_start_inv_pending = chapter == 1,
    }
    if chapter == 1 then
        pending_state.first_chapter_start_inv_given = {}
    end

    worldindex:QueueNextWorld({
        target = { type = "generated", level = preset, world_type = "adventure", cleanup_on_return = true },
        file_id = ADVENTURE_WORLD_INDEX_FILE_ID,
        reuse_existing = false,
        chapter = chapter,
        keep_session = true,
        pending_generation =
        {
            reason = "reset",
            chapter = chapter,
            current_preset = preset,
            player_sessions = chapter_player_snapshot,
            cleanup_session_id = run.current_session_id,
            file_id = ADVENTURE_WORLD_INDEX_FILE_ID,
            state = pending_state,
        },
    }, function(success, current_chapter)
        cb(success, current_chapter)
    end)
end

function ShardAdventureIndex:ResetCurrentChapterSecondary(opts, cb)
    local index = self.index
    local worldindex = index.worldindex
    if type(opts) == "function" and cb == nil then
        cb = opts
        opts = nil
    end
    cb = cb or NOOP
    opts = opts or {}

    local run = worldindex:GetState(ADVENTURE_WORLD_INDEX_FILE_ID)
    if run == nil or not run.active or not run.secondary or run.main == nil then
        print("[Adventure Mode] No active secondary adventure chapter to reset.")
        cb(false)
        return
    end

    local chapter = math.floor(tonumber(opts.chapter) or tonumber(run.chapter) or 1)
    if chapter ~= run.chapter or type(run.level_sequence) ~= "table" or run.level_sequence[chapter] == nil then
        print("[Adventure Mode] Cannot reset secondary adventure chapter "..tostring(chapter)..".")
        cb(false)
        return
    end

    local next_revision = get_next_adventure_chapter_revision(run, opts.chapter_revision)
    if next_revision == nil then
        print("[Adventure Mode] Cannot reset secondary adventure with a stale chapter revision.")
        cb(false)
        return
    end

    local preset = get_secondary_adventure_level()
    local target = build_secondary_adventure_target()
    worldindex:QueueNextWorld({
        target = { type = "generated", level = target, world_type = "adventure", cleanup_on_return = true },
        file_id = ADVENTURE_WORLD_INDEX_FILE_ID,
        reuse_existing = false,
        chapter = chapter,
        keep_session = true,
        pending_generation =
        {
            reason = "reset",
            chapter = chapter,
            current_preset = preset,
            player_sessions = nil,
            cleanup_session_id = run.current_session_id,
            file_id = ADVENTURE_WORLD_INDEX_FILE_ID,
            state =
            {
                chapter_revision = next_revision,
                first_chapter_start_inv_pending = false,
            },
            clear_fields = { "adventure_player_sessions" },
        },
    }, function(success, current_chapter)
        cb(success, current_chapter)
    end)
end

function ShardAdventureIndex:Complete(cb)
    return self:Advance(cb)
end

function ShardAdventureIndex:ReturnToMainWorld(reason, cb, opts)
    local index = self.index
    local worldindex = index.worldindex
    cb = cb or NOOP

    local run = worldindex:GetState(ADVENTURE_WORLD_INDEX_FILE_ID)
    if run == nil or not run.active or run.main == nil then
        print("[Adventure Mode] No active adventure to return from.")
        cb(false)
        return
    end

    inject_late_joiners_into_main_world(index, run, function(injected)
        if not injected then
            cb(false)
            return
        end
        worldindex:ReturnToStoredWorld(reason or "return", function(success)
            if success then
                if opts ~= nil and opts.defer_parent_restore then
                    cb(true)
                    return
                end
                local finished_run = worldindex:GetState(ADVENTURE_WORLD_INDEX_FILE_ID) or run
                worldindex:RestoreParentWorldIndex(finished_run, function(parent_restored)
                    cb(parent_restored == true)
                end)
                return
            end
            cb(success)
        end, run.main.player_sessions, opts)
    end)
end

function ShardAdventureIndex:Start(opts, cb)
    if type(opts) == "function" and cb == nil then
        cb = opts
        opts = nil
    end
    cb = cb or NOOP
    local index = self.index
    if index == nil then
        cb(false)
        return false
    end
    if TheShard ~= nil and not ShardWorldIndex:IsMasterShard() then
        print("[Adventure Mode] ShardGameIndex.adventure:Start must be called on the master shard.")
        cb(false)
        return false
    end
    opts = opts or {}
    local level_sequence, sequence_error = normalize_adventure_playlist(opts.level_sequence or self:BuildPlaylist())
    if level_sequence == nil then
        print("[Adventure Mode] Cannot start adventure: " .. tostring(sequence_error) .. ".")
        cb(false)
        return false
    end
    opts.level_sequence = level_sequence

    local initial_chapter = opts.chapter or 1
    if type(initial_chapter) ~= "number" then
        print("[Adventure Mode] Cannot start at chapter " .. tostring(initial_chapter) .. ".")
        cb(false)
        return false
    end
    initial_chapter = math.floor(initial_chapter)
    if initial_chapter < 1 or initial_chapter > #level_sequence then
        print("[Adventure Mode] Cannot start at chapter " .. tostring(initial_chapter) .. ".")
        cb(false)
        return false
    end
    opts.chapter = initial_chapter
    opts.chapter_revision = get_adventure_chapter_revision(opts.chapter_revision, 1)
    opts.run_id = get_adventure_run_id(opts.run_id) or create_adventure_run_id(index)

    return index.worldindex:RunSecondaryWorldIndexTransition({
        secondary_operation = "BeginSecondaryAdventure",
        secondary_data =
        {
            level_sequence = opts.level_sequence,
            chapter = opts.chapter,
            chapter_revision = opts.chapter_revision,
            sequence_id = opts.sequence_id,
            run_id = opts.run_id,
            reason = "begin",
        },
        rpc_namespace = "AdventureMode",
        secondary_shard_wait_timeout = opts.secondary_shard_wait_timeout,
        secondary_shard_wait_poll_interval = opts.secondary_shard_wait_poll_interval,
        force_players_to_master = true,
        force_players_to_master_modname = "AdventureMode",
        force_players_to_master_rpcname = "ForcePlayersToMaster",
    }, function(done)
        self:Begin(opts, done)
    end, function(success)
        if success then
            restart_current_slot_after_shard_rpc(index, { adventure_transition = "begin" })
        end
        cb(success)
    end)
end

function ShardAdventureIndex:AdvanceShard(opts, cb)
    if type(opts) == "function" and cb == nil then
        cb = opts
        opts = nil
    end
    cb = cb or NOOP
    local index = self.index
    if index == nil or not self:IsActive() or self._advance_pending or self._reset_pending or self._return_pending then
        cb(false)
        return false
    end
    if TheShard ~= nil and not ShardWorldIndex:IsMasterShard() then
        print("[Adventure Mode] ShardGameIndex.adventure:AdvanceShard must be called on the master shard.")
        cb(false)
        return false
    end

    opts = opts or {}
    local run = self:EnsureRunID()
    local requested_chapter = math.floor(tonumber(opts.chapter) or ((run.chapter or 1) + 1))
    local requested_revision = get_next_adventure_chapter_revision(run, opts.chapter_revision)
    if requested_chapter <= #run.level_sequence and requested_revision == nil then
        print("[Adventure Mode] Cannot advance with a stale chapter revision.")
        cb(false)
        return false
    end
    opts.chapter_revision = requested_revision
    local operation = requested_chapter > #run.level_sequence and
        "ReturnSecondaryAdventure" or "AdvanceSecondaryAdventure"
    local secondary_opts =
    {
        reason = operation == "ReturnSecondaryAdventure" and "complete" or "advance",
        run_id = run.run_id,
        sequence_id = run.sequence_id,
    }
    if operation ~= "ReturnSecondaryAdventure" then
        secondary_opts.chapter = requested_chapter
        secondary_opts.chapter_revision = requested_revision
    end

    self._advance_pending = true
    local completed = false
    local function finish(success)
        if completed then
            return
        end
        completed = true
        if success ~= true then
            self._advance_pending = false
        end
        cb(success == true)
    end

    return index.worldindex:RunSecondaryWorldIndexTransition({
        secondary_operation = operation,
        secondary_data = secondary_opts,
        rpc_namespace = "AdventureMode",
        secondary_shard_wait_timeout = opts.secondary_shard_wait_timeout,
        secondary_shard_wait_poll_interval = opts.secondary_shard_wait_poll_interval,
        save_current = false,
    }, function(done)
        if operation == "ReturnSecondaryAdventure" then
            self:ReturnToMainWorld("complete", done,
            {
                defer_cleanup = true,
                defer_parent_restore = true,
            })
        else
            self:Advance(opts, done)
        end
    end, function(success, phase)
        if success and operation ~= "ReturnSecondaryAdventure" then
            restart_current_slot_after_shard_rpc(index, { adventure_transition = "advance" })
            finish(true)
            return
        end

        if success then
            local finished_run = self:GetState()
            index.worldindex:FinalizeDeferredReturn(finished_run, function(finalized)
                if not finalized then
                    print("[Adventure Mode] Deferred return cleanup will resume after restart.")
                end
                restart_current_slot_after_shard_rpc(index)
                finish(true)
            end)
            return
        end

        if phase == "local" or
            phase == "commit" and operation ~= "ReturnSecondaryAdventure" then
            index.worldindex:RollbackPendingGeneration(function(rolled_back, was_pending)
                if was_pending and not rolled_back then
                    print("[Adventure Mode] Pending chapter rollback will resume after restart.")
                    restart_current_slot_after_shard_rpc(index)
                end
                finish(false)
            end, ADVENTURE_WORLD_INDEX_FILE_ID)
        elseif phase == "commit" then
            index.worldindex:RollbackDeferredReturn(self:GetState(), function()
                finish(false)
            end)
        else
            finish(false)
        end
    end)
end

function ShardAdventureIndex:CompleteShard(opts, cb)
    return self:AdvanceShard(opts, cb)
end

function ShardAdventureIndex:FinishForwardedReset(request_id, success)
    if request_id ~= self._forwarded_reset_request_id then
        return false
    end

    if self._forwarded_reset_timeout_task ~= nil then
        self._forwarded_reset_timeout_task:Cancel()
        self._forwarded_reset_timeout_task = nil
    end
    self._forwarded_reset_request_id = nil

    local callbacks = self._reset_callbacks or {}
    self._reset_callbacks = nil
    if success ~= true then
        self._reset_pending = false
    end
    for _, callback in ipairs(callbacks) do
        callback(success == true)
    end
    return true
end

function ShardAdventureIndex:FinishForwardedReturn(request_id, success)
    if request_id ~= self._forwarded_return_request_id then
        return false
    end

    if self._forwarded_return_timeout_task ~= nil then
        self._forwarded_return_timeout_task:Cancel()
        self._forwarded_return_timeout_task = nil
    end
    self._forwarded_return_request_id = nil

    local callbacks = self._return_callbacks or {}
    self._return_callbacks = nil
    self._return_pending = false
    for _, callback in ipairs(callbacks) do
        callback(success == true)
    end
    return true
end

function ShardAdventureIndex:ResetCurrentChapterShard(opts, cb)
    if type(opts) == "function" and cb == nil then
        cb = opts
        opts = nil
    end
    cb = cb or NOOP
    opts = opts or {}

    local index = self.index
    if index == nil then
        cb(false)
        return false
    end

    if self._reset_pending then
        if self._reset_callbacks ~= nil then
            table.insert(self._reset_callbacks, cb)
        else
            cb(true)
        end
        return true
    end

    if not self:IsActive() or self._advance_pending or self._return_pending then
        cb(false)
        return false
    end

    local run = self:EnsureRunID()
    if run == nil then
        cb(false)
        return false
    end

    if TheShard ~= nil and not ShardWorldIndex:IsMasterShard() then
        local request_id = create_adventure_reset_request_id(index)
        self._reset_pending = true
        self._reset_callbacks = { cb }
        self._forwarded_reset_request_id = request_id
        send_master_adventure_rpc("ResetAdventureWorld", {
            request_id = request_id,
            reason = opts.reason or "worldreset",
            run_id = run.run_id,
            sequence_id = run.sequence_id,
            chapter = run.chapter,
            chapter_revision = get_adventure_chapter_revision(run.chapter_revision, 1),
        })
        if TheWorld ~= nil then
            self._forwarded_reset_timeout_task = TheWorld:DoStaticTaskInTime(FORWARDED_RESET_TIMEOUT, function()
                self._forwarded_reset_timeout_task = nil
                self:FinishForwardedReset(request_id, false)
            end)
        else
            self:FinishForwardedReset(request_id, false)
        end
        return true
    end

    local chapter = math.floor(tonumber(run ~= nil and run.chapter or nil) or 1)
    local chapter_revision = get_next_adventure_chapter_revision(run, opts.chapter_revision)
    if run == nil or type(run.level_sequence) ~= "table" or run.level_sequence[chapter] == nil or chapter_revision == nil then
        cb(false)
        return false
    end
    opts.chapter = chapter
    opts.chapter_revision = chapter_revision

    self._reset_pending = true
    self._reset_callbacks = { cb }
    local completed = false
    local function finish(success)
        if completed then
            return
        end
        completed = true

        local callbacks = self._reset_callbacks or {}
        self._reset_callbacks = nil
        if not success then
            self._reset_pending = false
            restart_current_slot_after_shard_rpc(index)
        end
        for _, callback in ipairs(callbacks) do
            callback(success)
        end
    end

    return index.worldindex:RunSecondaryWorldIndexTransition({
        secondary_operation = "ResetSecondaryAdventure",
        secondary_data =
        {
            chapter = chapter,
            chapter_revision = chapter_revision,
            run_id = run.run_id,
            sequence_id = run.sequence_id,
            reason = opts.reason or "worldreset",
        },
        rpc_namespace = "AdventureMode",
        secondary_prepare_timeout = opts.secondary_shard_wait_timeout,
        secondary_shard_wait_timeout = opts.secondary_shard_wait_timeout,
        secondary_shard_wait_poll_interval = opts.secondary_shard_wait_poll_interval,
        force_players_to_master = true,
        force_players_to_master_modname = "AdventureMode",
        force_players_to_master_rpcname = "ForcePlayersToMaster",
        save_current_on_wait_failure = true,
    }, function(done)
        self:ResetCurrentChapter(opts, done)
    end, function(success, phase)
        if success then
            if TheWorld ~= nil then
                TheWorld:PushEvent("ms_worldreset")
            end
            restart_current_slot_after_shard_rpc(index, { adventure_transition = "reset" })
            finish(true)
            return
        end

        if phase == "local" or phase == "commit" then
            index.worldindex:RollbackPendingGeneration(function(rolled_back, was_pending)
                if phase == "local" then
                    if was_pending and not rolled_back then
                        print("[Adventure Mode] Pending chapter reset rollback will resume after restart.")
                    end
                elseif not rolled_back then
                    print("[Adventure Mode] Pending chapter reset rollback will resume after restart.")
                end
                finish(false)
            end, ADVENTURE_WORLD_INDEX_FILE_ID)
        else
            finish(false)
        end
    end)
end

function ShardAdventureIndex:ReturnFromShard(reason, cb)
    cb = cb or NOOP
    local index = self.index
    if index == nil then
        cb(false)
        return false
    end

    if self._return_pending then
        if self._return_callbacks ~= nil then
            table.insert(self._return_callbacks, cb)
        else
            cb(true)
        end
        return true
    end

    if not self:IsActive() or self._advance_pending or self._reset_pending then
        cb(false)
        return false
    end

    local run = self:EnsureRunID()
    if run == nil then
        cb(false)
        return false
    end

    if TheShard ~= nil and not ShardWorldIndex:IsMasterShard() then
        local request_id = create_adventure_return_request_id(index)
        self._return_pending = true
        self._return_callbacks = { cb }
        self._forwarded_return_request_id = request_id
        send_master_adventure_rpc("ReturnFromAdventure", {
            request_id = request_id,
            reason = reason or "return",
            run_id = run.run_id,
            sequence_id = run.sequence_id,
        })
        if TheWorld ~= nil then
            self._forwarded_return_timeout_task = TheWorld:DoStaticTaskInTime(FORWARDED_RETURN_TIMEOUT, function()
                self._forwarded_return_timeout_task = nil
                self:FinishForwardedReturn(request_id, false)
            end)
        else
            self:FinishForwardedReturn(request_id, false)
        end
        return true
    end

    self._return_pending = true
    self._return_callbacks = { cb }
    local completed = false
    local function finish(success)
        if completed then
            return
        end
        completed = true

        local callbacks = self._return_callbacks
        self._return_callbacks = nil
        if not success then
            self._return_pending = false
        end
        for _, callback in ipairs(callbacks) do
            callback(success)
        end
    end

    return index.worldindex:RunSecondaryWorldIndexTransition({
        secondary_operation = "ReturnSecondaryAdventure",
        secondary_data =
        {
            reason = reason or "return",
            run_id = run ~= nil and run.run_id or nil,
            sequence_id = run ~= nil and run.sequence_id or nil,
        },
        rpc_namespace = "AdventureMode",
        force_players_to_master = true,
        force_players_to_master_modname = "AdventureMode",
        force_players_to_master_rpcname = "ForcePlayersToMaster",
    }, function(done)
        self:ReturnToMainWorld(reason or "return", done,
        {
            defer_cleanup = true,
            defer_parent_restore = true,
        })
    end, function(success, phase)
        if success then
            local finished_run = self:GetState()
            index.worldindex:FinalizeDeferredReturn(finished_run, function(finalized)
                if not finalized then
                    print("[Adventure Mode] Deferred return cleanup will resume after restart.")
                end
                restart_current_slot_after_shard_rpc(index)
                finish(true)
            end)
        elseif phase == "commit" then
            index.worldindex:RollbackDeferredReturn(self:GetState(), function()
                finish(false)
            end)
        else
            finish(false)
        end
    end)
end

local function get_secondary_adventure_target(index, opts, operation)
    if operation ~= "BeginSecondaryAdventure" and
        operation ~= "AdvanceSecondaryAdventure" and
        operation ~= "ResetSecondaryAdventure" then
        return nil, ADVENTURE_WORLD_INDEX_FILE_ID
    end

    return
    {
        type = "generated",
        level = build_secondary_adventure_target(),
        world_type = "adventure",
        cleanup_on_return = true,
    },
    ADVENTURE_WORLD_INDEX_FILE_ID
end

local function validate_secondary_adventure(index, opts, active_state, operation)
    if operation == "BeginSecondaryAdventure" then
        return true
    end
    if active_state == nil or active_state.kind ~= "adventure" then
        return false, "active world index is not an adventure"
    end

    local run_id = type(active_state.run_id) == "string" and active_state.run_id ~= "" and active_state.run_id or nil
    local requested_run_id = type(opts.run_id) == "string" and opts.run_id ~= "" and opts.run_id or nil
    if run_id ~= requested_run_id then
        return false, "adventure run id does not match"
    end
    if (active_state.sequence_id or "default") ~= (opts.sequence_id or "default") then
        return false, "adventure sequence id does not match"
    end

    if operation == "ResetSecondaryAdventure" then
        local current_chapter = math.floor(tonumber(active_state.chapter) or 0)
        local requested_chapter = math.floor(tonumber(opts.chapter) or current_chapter)
        local current_revision = math.floor(tonumber(active_state.chapter_revision) or 1)
        local requested_revision = math.floor(tonumber(opts.chapter_revision) or 0)
        if requested_chapter ~= current_chapter then
            return false, "reset chapter does not match current chapter"
        end
        if requested_revision <= current_revision then
            return false, "reset chapter revision is stale"
        end
    end

    return true
end

local function register_secondary_adventure_handler(operation, opts)
    ShardWorldIndex:RegisterSecondaryTransitionHandler(operation,
    {
        kind = "adventure",
        is_begin = opts.is_begin == true,
        allows_active_world_index = opts.allows_active_world_index == true,
        needs_target = opts.needs_target ~= false,
        GetTarget = function(index, data)
            return get_secondary_adventure_target(index, data, operation)
        end,
        Validate = function(index, data, active_state)
            return validate_secondary_adventure(index, data, active_state, operation)
        end,
        Dispatch = opts.dispatch,
    })
end

register_secondary_adventure_handler("BeginSecondaryAdventure",
{
    is_begin = true,
    allows_active_world_index = true,
    dispatch = function(index, opts, _, cb)
        if index.adventure == nil then
            cb(false)
            return
        end
        index.adventure:BeginSecondary(opts, cb)
    end,
})

register_secondary_adventure_handler("AdvanceSecondaryAdventure",
{
    dispatch = function(index, opts, _, cb)
        if index.adventure == nil then
            cb(false)
            return
        end
        index.adventure:AdvanceSecondary(opts, cb)
    end,
})

register_secondary_adventure_handler("ResetSecondaryAdventure",
{
    dispatch = function(index, opts, _, cb)
        if index.adventure == nil then
            cb(false)
            return
        end
        index.adventure:ResetCurrentChapterSecondary(opts, cb)
    end,
})

register_secondary_adventure_handler("ReturnSecondaryAdventure",
{
    needs_target = false,
    dispatch = function(index, opts, _, cb)
        if index.adventure == nil then
            cb(false)
            return
        end
        index.adventure:ReturnToMainWorld(opts.reason or "return", cb,
        {
            defer_cleanup = true,
            defer_parent_restore = true,
        })
    end,
})
