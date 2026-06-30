-- Adventure state manager for ShardIndex.
-- ShardIndex patching stays in postinit/shardindex.lua; this class owns the
-- adventure sidecar, chapter transitions, player sessions, and shard sync flow.

GLOBAL.setfenv(1, GLOBAL)

local ShardWorldIndex = ShardWorldIndex

ShardAdventureIndex = Class(function(self, index)
    self.index = index
end)

local ADVENTURE_INDEX_FILE = "adventure"
local ADVENTURE_DEATH_CHECK_POLL_INTERVAL = 0.25
local ADVENTURE_DEATH_CHECK_INITIAL_DELAY = 0.1

local function NOOP()
    ShardWorldIndex:Noop()
end

local function get_sidecar_filename(index)
    return index:GetShardIndexName().."_"..ADVENTURE_INDEX_FILE
end

local function read_sidecar(index, cb)
    cb = cb or NOOP

    local filename = get_sidecar_filename(index)
    local slot, shard = ShardWorldIndex:GetSlotAndShard(index)
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
    cb = cb or NOOP

    local filename = get_sidecar_filename(index)
    local str = DataDumper(data or {}, nil, false)
    local slot, shard = ShardWorldIndex:GetSlotAndShard(index)
    if slot ~= nil and shard ~= nil then
        TheSim:SetPersistentStringInClusterSlot(slot, shard, filename, str, false, cb)
    else
        TheSim:SetPersistentString(filename, str, false, cb)
    end
end

local set_adventure_state

local function clear_adventure_sidecar(index, cb)
    set_adventure_state(index, nil)
    write_sidecar(index, nil, cb)
end

local function is_adventure_transition_restart()
    return Settings ~= nil and
        Settings.reset_action == RESET_ACTION.LOAD_SLOT and
        Settings.adventure_transition ~= nil
end

local function is_adventure_load_slot()
    return Settings ~= nil and Settings.reset_action == RESET_ACTION.LOAD_SLOT
end

local function is_pending_adventure_generation_state(state)
    return state ~= nil and
        state.active == true and
        state.main ~= nil and
        state.main.session_id ~= nil and
        state.main.session_id ~= "" and
        (type(state.pending_generation) == "table" or
        ((state.current_session_id == nil or state.current_session_id == "") and state.current_preset ~= nil))
end

local function should_preserve_pending_adventure_generation(state)
    return is_adventure_transition_restart() or
        (is_adventure_load_slot() and is_pending_adventure_generation_state(state))
end

local function clear_interrupted_adventure_transition(index, cb)
    cb = cb or NOOP

    clear_adventure_sidecar(index, function()
        ShardWorldIndex:RestoreWorldgenOverride(index, nil, cb)
    end)
end

local function prepare_interrupted_adventure_regen(index)
    index.world = { options = {} }
    index.server = {}
    index.enabled_mods = {}
    index.session_id = nil
    index:MarkDirty()
end

local function adventure_state_has_origin(state)
    return state ~= nil and (state.slot ~= nil or state.shard ~= nil)
end

local function adventure_state_matches_index(index, state)
    if state == nil then
        return false
    end
    if state.slot ~= nil and state.slot ~= index:GetSlot() then
        return false
    end
    return state.shard == nil or state.shard == ShardWorldIndex:GetIndexShard(index)
end

local function finish_interrupted_return_to_main(index, state, cb)
    cb = cb or NOOP

    if state.main == nil or state.main.session_id == nil or state.main.session_id == "" then
        clear_adventure_sidecar(index, cb)
        return
    end

    state.active = false
    state.finished_at = state.finished_at or os.time()
    state.return_reason = state.return_reason or "interrupted_return"

    ShardWorldIndex:SwitchIndexToExistingWorld(index, state.main)

    ShardWorldIndex:RestoreWorldgenOverride(index, state.main.worldgenoverride, function()
        index:Save(function()
            write_sidecar(index, state, function()
                set_adventure_state(index, state)
                cb()
            end)
        end)
    end)
end

local function apply_pending_adventure_generation_state(state)
    local pending = type(state.pending_generation) == "table" and state.pending_generation or nil
    if pending == nil then
        return
    end

    state.reason = pending.reason or state.reason
    state.chapter = pending.chapter or state.chapter
    state.current_preset = pending.current_preset or state.current_preset
    state.current_session_id = nil
    state.player_sessions = ShardWorldIndex:DeepCopy(pending.player_sessions)
    state.adventure_player_sessions = ShardWorldIndex:DeepCopy(pending.adventure_player_sessions)
    state.first_chapter_start_inv_pending = pending.first_chapter_start_inv_pending == true
    state.cleanup_session_id = pending.cleanup_session_id
    state.pending_generation = nil
    state.updated_at = os.time()
end

local function load_adventure_sidecar_state(index, state, cb)
    cb = cb or NOOP

    if state == nil or not state.active then
        set_adventure_state(index, state)
        cb()
        return
    end

    if adventure_state_has_origin(state) and not adventure_state_matches_index(index, state) then
        print("[Adventure Mode] Clearing adventure sidecar from another slot or shard.")
        clear_adventure_sidecar(index, cb)
        return
    end

    if is_adventure_transition_restart() then
        set_adventure_state(index, state)
        cb()
        return
    end

    local session_id = index:GetSession()
    if session_id == nil or session_id == "" then
        if is_pending_adventure_generation_state(state) then
            print("[Adventure Mode] Resuming interrupted adventure world generation.")
            apply_pending_adventure_generation_state(state)
            set_adventure_state(index, state)
            cb()
            return
        end

        if adventure_state_matches_index(index, state) then
            print("[Adventure Mode] Restoring main world after interrupted adventure transition.")
            finish_interrupted_return_to_main(index, state, cb)
        else
            print("[Adventure Mode] Clearing interrupted adventure transition before regenerating the slot.")
            prepare_interrupted_adventure_regen(index)
            clear_interrupted_adventure_transition(index, cb)
        end
        return
    end

    if type(state.pending_generation) == "table" then
        ShardWorldIndex:WorldSessionExists(index, session_id, function(exists)
            if exists then
                set_adventure_state(index, state)
                cb()
            else
                print("[Adventure Mode] Current adventure session is missing; returning to stashed main world.")
                finish_interrupted_return_to_main(index, state, cb)
            end
        end)
        return
    end

    if state.current_session_id == session_id then
        ShardWorldIndex:WorldSessionExists(index, session_id, function(exists)
            if exists then
                set_adventure_state(index, state)
                cb()
            else
                print("[Adventure Mode] Current adventure session is missing; returning to stashed main world.")
                finish_interrupted_return_to_main(index, state, cb)
            end
        end)
        return
    end

    if state.main ~= nil and state.main.session_id == session_id then
        print("[Adventure Mode] Finishing interrupted return to main world.")
        finish_interrupted_return_to_main(index, state, cb)
        return
    end

    print("[Adventure Mode] Clearing stale adventure sidecar for unrelated session.")
    clear_adventure_sidecar(index, cb)
end

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

    ShardWorldIndex:InjectPlayerSessionsIntoExistingWorld(index, state.main.session_id, sessions, cb)
end

local function get_adventure_state(index)
    if TheWorld ~= nil and not TheWorld.ismastersim and TheWorld.net ~= nil and
        TheWorld.net.components ~= nil and TheWorld.net.components.adventurestate ~= nil then
        local state = TheWorld.net.components.adventurestate:GetState()
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

    return index.adventure_state
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

    if TheShard ~= nil and TheShard.GetSecondaryShardPlayerCounts ~= nil and ShardWorldIndex:IsMasterShard() then
        local secondary_players, secondary_ghosts = TheShard:GetSecondaryShardPlayerCounts(USERFLAGS.IS_GHOST)
        secondary_players = secondary_players or 0
        secondary_ghosts = secondary_ghosts or 0
        total = total + secondary_players
        alive = alive + math.max(secondary_players - secondary_ghosts, 0)
    end

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

function give_adventure_first_chapter_start_inv(index, inst)
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
    ShardWorldIndex:RestartCurrentSlotAfterShardRPC(index, extra_params)
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

-- Force the adventure level's worldgenoverride. Without this, SetServerShardData
-- re-applies the MAIN world's worldgenoverride on the next boot and we generate
-- the wrong world. When both presets are supplied, GetWorldgenOverride does a
-- full override; otherwise the generated override merges onto self.world.options.
local function write_adventure_worldgenoverride(index, level, cb)
    ShardWorldIndex:WriteLevelWorldgenOverride(index, level, cb)
end

local function get_adventure_preset_id(preset)
    if type(preset) == "table" then
        return preset.id or preset.worldgen_preset or preset.preset or preset.settings_preset
    end
    return preset
end

local function BuildAdventureClientState(state)
    if state == nil then
        return nil
    end

    local total_chapters = type(state.level_sequence) == "table" and #state.level_sequence or nil

    return
    {
        active = state.active == true,
        secondary = state.secondary == true or nil,
        reason = state.reason,
        sequence_id = state.sequence_id,
        chapter = state.chapter,
        current_preset = get_adventure_preset_id(state.current_preset),
        current_session_id = state.current_session_id,
        total_chapters = total_chapters,
        started_at = state.started_at,
        updated_at = state.updated_at,
        finished_at = state.finished_at,
        return_reason = state.return_reason,
    }
end

local function get_adventure_preset(index)
    local state = get_adventure_state(index)
    return get_adventure_preset_id(state ~= nil and state.current_preset or nil)
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

function set_adventure_state(index, state)
    index.adventure_state = state

    if TheWorld ~= nil and TheWorld.ismastersim and TheWorld.net ~= nil and
        TheWorld.net.components ~= nil and TheWorld.net.components.adventurestate ~= nil then
        TheWorld.net.components.adventurestate:SetState(state)
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


local LEVEL_DEFS = {
    { id = "RAINY",      min_playlist_position = 1, max_playlist_position = 3 },
    { id = "WINTER",     min_playlist_position = 1, max_playlist_position = 4 },
    { id = "HUB",        min_playlist_position = 1, max_playlist_position = 4 },
    { id = "ISLANDHOP",  min_playlist_position = 1, max_playlist_position = 4 },
    { id = "TWOLANDS",   min_playlist_position = 3, max_playlist_position = 4 },
    { id = "DARKNESS",   min_playlist_position = CAMPAIGN_LENGTH,     max_playlist_position = CAMPAIGN_LENGTH },
    { id = "ENDING",     min_playlist_position = CAMPAIGN_LENGTH + 1, max_playlist_position = CAMPAIGN_LENGTH + 1 },
}

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
    local index = self.index
    read_sidecar(index, function(state)
        load_adventure_sidecar_state(index, state, cb)
    end)
end

function ShardAdventureIndex:ClearSidecar(cb)
    clear_adventure_sidecar(self.index, cb)
end

function ShardAdventureIndex:NeedsGenerationOnLoad()
    return is_adventure_load_slot() and
        is_pending_adventure_generation_state(get_adventure_state(self.index))
end

function ShardAdventureIndex:ReservesSlot()
    local state = get_adventure_state(self.index)
    return state ~= nil and
        state.active == true and
        not is_adventure_load_slot() and
        state.main ~= nil and
        state.main.session_id ~= nil and
        state.main.session_id ~= ""
end

function ShardAdventureIndex:DeleteWithOriginal(delete_fn, cb, save_options)
    local index = self.index
    local state = get_adventure_state(index)
    if save_options and state ~= nil and state.active and should_preserve_pending_adventure_generation(state) then
        index:MarkDirty()
        index:Save(function(...)
            local args = { ... }
            set_adventure_state(index, state)
            write_sidecar(index, state, function()
                if cb ~= nil then
                    cb(unpack(args))
                end
            end)
        end)
        return
    end

    if save_options and state ~= nil and state.active then
        prepare_interrupted_adventure_regen(index)
    end

    clear_adventure_sidecar(index, function()
        delete_fn(index, cb, save_options)
    end)
end

function ShardAdventureIndex:SetServerShardDataWithOriginal(set_server_shard_data_fn, customoptions, serverdata, onsavedcb)
    local index = self.index
    local state = get_adventure_state(index)
    if state ~= nil and state.active and not should_preserve_pending_adventure_generation(state) then
        prepare_interrupted_adventure_regen(index)
        clear_interrupted_adventure_transition(index, function()
            set_server_shard_data_fn(index, customoptions, serverdata, onsavedcb)
        end)
        return
    end

    if state ~= nil and not state.active then
        clear_adventure_sidecar(index, function()
            set_server_shard_data_fn(index, customoptions, serverdata, onsavedcb)
        end)
        return
    end

    set_server_shard_data_fn(index, customoptions, serverdata, onsavedcb)
end

function ShardAdventureIndex:OnGenerateNewWorldWithOriginal(on_generate_new_world_fn, savedata, metadataStr, session_identifier, cb)
    local index = self.index
    local state = get_adventure_state(index)
    if state ~= nil and state.active then
        apply_pending_adventure_generation_state(state)
        state.current_session_id = session_identifier
        state.updated_at = os.time()
        if savedata ~= nil and savedata.map ~= nil and savedata.map.topology ~= nil then
            savedata.map.topology.adventure_state = BuildAdventureClientState(state)
        end
    end

    on_generate_new_world_fn(index, savedata, metadataStr, session_identifier, function(...)
        local args = { ... }
        state = get_adventure_state(index)
        if state ~= nil and state.active then
            state.current_session_id = session_identifier
            state.updated_at = os.time()
            local should_mark_injected = type(state.player_sessions) == "table" and
                #state.player_sessions > 0 and
                session_identifier ~= nil and
                session_identifier ~= "" and
                TheNet:GetIsServer()
            ShardWorldIndex:InjectPlayerSessionsIntoWorld(index, state.player_sessions, session_identifier, savedata, function()
                if should_mark_injected then
                    state.player_sessions = nil
                    state.last_player_session_injected = session_identifier
                end
                local cleanup_session_id = state.cleanup_session_id
                state.cleanup_session_id = nil
                write_sidecar(index, state, function()
                    ShardWorldIndex:DeleteSessionIfNotHome(cleanup_session_id, state.main.session_id)
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

function ShardAdventureIndex:BuildPlaylist()
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

    local level_sequence = opts.level_sequence or self:BuildPlaylist()
    if #level_sequence == 0 then
        print("[Adventure Mode] Empty level_sequence.")
        cb(false)
        return
    end

    local first_preset = ShardWorldIndex:GetLevelForShard(level_sequence[1], ShardWorldIndex:GetIndexShard(index))
    local previous_state = get_adventure_state(index)

    -- Stash the MAIN world's worldgenoverride verbatim before we overwrite it,
    -- so AdventureReturnToMainWorld can put it back exactly as it was.
    ShardWorldIndex:ReadWorldgenOverrideRaw(index, function(main_wgo)
        local main_player_sessions = opts.player_sessions or ShardWorldIndex:CollectPlayerSessions()
        local state =
        {
            active = true,
            reason = "begin",
            sequence_id = opts.sequence_id or "default",
            slot = index:GetSlot(),
            shard = ShardWorldIndex:GetIndexShard(index),
            started_at = os.time(),
            updated_at = os.time(),

            level_sequence = ShardWorldIndex:DeepCopy(level_sequence),
            chapter = 1,
            current_preset = first_preset,
            current_session_id = nil,
            player_sessions = ShardWorldIndex:GetCharacterOnlySessions(main_player_sessions),
            participants = ShardWorldIndex:SessionsToUseridMap(main_player_sessions),
            late_joiners = {},
            adventure_player_sessions = {},
            first_chapter_start_inv_pending = true,
            first_chapter_start_inv_given = {},
            maxwell_intro_played_chapters = {},
            maxwell_throne_puppet = get_maxwell_throne_puppet_record(previous_state ~= nil and previous_state.maxwell_throne_puppet or nil),

            main =
            {
                session_id = main_session,
                worldgenoverride = main_wgo,
                world = ShardWorldIndex:DeepCopy(index.world),
                server = ShardWorldIndex:DeepCopy(index.server),
                enabled_mods = ShardWorldIndex:DeepCopy(index.enabled_mods),
                return_position = opts.return_position or ShardWorldIndex:GetReturnPosition(),
                player_sessions = main_player_sessions,
            },
        }

        set_adventure_state(index, state)
        ShardWorldIndex:SwitchIndexToGeneratedWorld(index, first_preset, true)

        write_adventure_worldgenoverride(index, first_preset, function()
            write_sidecar(index, state, function()
                index:Save(function()
                    cb(true)
                end)
            end)
        end)
    end)
end

function ShardAdventureIndex:BeginSecondary(opts, cb)
    local index = self.index
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

    local level_sequence = opts.level_sequence
    if type(level_sequence) ~= "table" or #level_sequence == 0 then
        print("[Adventure Mode] Empty secondary level_sequence.")
        cb(false)
        return
    end

    ShardWorldIndex:ReadWorldgenOverrideRaw(index, function(home_wgo)
        local state =
        {
            active = true,
            secondary = true,
            reason = "begin",
            sequence_id = opts.sequence_id or "default",
            slot = index:GetSlot(),
            shard = ShardWorldIndex:GetIndexShard(index),
            started_at = os.time(),
            updated_at = os.time(),

            level_sequence = ShardWorldIndex:DeepCopy(level_sequence),
            chapter = 1,
            current_preset = ShardWorldIndex:GetLevelForShard(level_sequence[1], ShardWorldIndex:GetIndexShard(index)),
            current_session_id = nil,
            player_sessions = nil,
            adventure_player_sessions = {},
            first_chapter_start_inv_pending = false,
            first_chapter_start_inv_given = {},
            maxwell_intro_played_chapters = {},

            main =
            {
                session_id = home_session,
                worldgenoverride = home_wgo,
                world = ShardWorldIndex:DeepCopy(index.world),
                server = ShardWorldIndex:DeepCopy(index.server),
                enabled_mods = ShardWorldIndex:DeepCopy(index.enabled_mods),
            },
        }

        set_adventure_state(index, state)
        ShardWorldIndex:SwitchIndexToGeneratedWorld(index, state.current_preset, true)

        write_adventure_worldgenoverride(index, state.current_preset, function()
            write_sidecar(index, state, function()
                index:Save(function()
                    cb(true)
                end)
            end)
        end)
    end)
end

-- Advance to the next chapter in the sequence, generating a fresh world. If the
-- current chapter is the last one, return to the main world instead.
function ShardAdventureIndex:Advance(opts, cb)
    local index = self.index
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

    local next_preset = ShardWorldIndex:GetLevelForShard(state.level_sequence[next_chapter], ShardWorldIndex:GetIndexShard(index))
    local player_sessions = opts.player_sessions or ShardWorldIndex:CollectPlayerSessions()
    local next_player_sessions = ShardWorldIndex:MergeSessionLists(player_sessions, state.adventure_player_sessions)
    state.pending_generation =
    {
        reason = "advance",
        chapter = next_chapter,
        current_preset = next_preset,
        player_sessions = next_player_sessions,
        adventure_player_sessions = ShardWorldIndex:DeepCopy(next_player_sessions) or {},
        first_chapter_start_inv_pending = false,
        cleanup_session_id = state.current_session_id,
    }
    state.updated_at = os.time()

    write_sidecar(index, state, function()
        apply_pending_adventure_generation_state(state)
        set_adventure_state(index, state)
        ShardWorldIndex:SwitchIndexToGeneratedWorld(index, next_preset, true)

        write_adventure_worldgenoverride(index, next_preset, function()
            index:Save(function()
                cb(true, next_chapter)
            end)
        end)
    end)
end

function ShardAdventureIndex:AdvanceSecondary(opts, cb)
    local index = self.index
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

    local next_preset = ShardWorldIndex:GetLevelForShard(state.level_sequence[next_chapter], ShardWorldIndex:GetIndexShard(index))
    state.pending_generation =
    {
        reason = "advance",
        chapter = next_chapter,
        current_preset = next_preset,
        player_sessions = nil,
        adventure_player_sessions = nil,
        first_chapter_start_inv_pending = false,
        cleanup_session_id = state.current_session_id,
    }
    state.updated_at = os.time()

    write_sidecar(index, state, function()
        apply_pending_adventure_generation_state(state)
        set_adventure_state(index, state)
        ShardWorldIndex:SwitchIndexToGeneratedWorld(index, next_preset, true)

        write_adventure_worldgenoverride(index, next_preset, function()
            index:Save(function()
                cb(true, next_chapter)
            end)
        end)
    end)
end

function ShardAdventureIndex:Complete(cb)
    return self:Advance(cb)
end

function ShardAdventureIndex:ReturnToMainWorld(reason, cb)
    local index = self.index
    cb = cb or NOOP

    local state = get_adventure_state(index)
    if state == nil or not state.active or state.main == nil then
        print("[Adventure Mode] No active adventure to return from.")
        cb(false)
        return
    end

    inject_late_joiners_into_main_world(index, state, function()
        -- Delete the adventure world we are leaving; keep the stashed main session.
        ShardWorldIndex:DeleteSessionIfNotHome(state.current_session_id, state.main.session_id)

        ShardWorldIndex:SwitchIndexToExistingWorld(index, state.main)
        state.active = false
        state.finished_at = os.time()
        state.return_reason = reason or "return"

        -- Restore the main world's worldgenoverride so a later main-world regen
        -- doesn't pick up the adventure preset.
        ShardWorldIndex:RestoreWorldgenOverride(index, state.main.worldgenoverride, function()
            index:Save(function()
                write_sidecar(index, state, function()
                    set_adventure_state(index, state)
                    cb(true)
                end)
            end)
        end)
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
    opts.level_sequence = opts.level_sequence or self:BuildPlaylist()

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
