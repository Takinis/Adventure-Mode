local AddModRPCHandler = AddModRPCHandler
local AddClientModRPCHandler = AddClientModRPCHandler
local AddShardModRPCHandler = AddShardModRPCHandler
GLOBAL.setfenv(1, GLOBAL)

local Levels = require("map/levels")
local EndGameDialog = require("screens/endgamedialog")

AddClientModRPCHandler("AdventureMode", "StartAdventurePresentation", function(presentation_id, preset, chapter, total, play_maxwell_intro, wait_for_players)
    if type(presentation_id) ~= "string" or presentation_id == "" or
        type(chapter) ~= "number" or type(total) ~= "number" then
        return
    end

    if TheFrontEnd ~= nil then
        local level = type(preset) == "string" and Levels.GetNameForLevelID(preset) or nil
        level = level or tostring(preset or "Adventure")
        local chapter_text = preset == "ENDING" and STRINGS.UI.SANDBOXMENU.CHAPTERS[6] or
            string.format(STRINGS.UI.SANDBOXMENU.ADVENTURECHAPTER, chapter, total)
        TheFrontEnd:QueueAdventurePresentation(
            presentation_id,
            level,
            chapter_text,
            play_maxwell_intro == true,
            wait_for_players == true
        )
    end
end)

AddClientModRPCHandler("AdventureMode", "StartAdventureTitle", function(presentation_id)
    if type(presentation_id) ~= "string" or presentation_id == "" then
        return
    end

    if TheFrontEnd ~= nil then
        TheFrontEnd:StartAdventureTitle(presentation_id)
    end
end)

AddClientModRPCHandler("AdventureMode", "StartMaxwellIntro", function(presentation_id, guid, x, y, z, can_skip)
    if type(presentation_id) ~= "string" or presentation_id == "" or type(guid) ~= "number" or
        type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" or type(can_skip) ~= "boolean" then
        return
    end

    if TheFrontEnd ~= nil then
        TheFrontEnd:StartMaxwellIntroCutscene(presentation_id, guid, x, y, z, can_skip)
    end
end)

AddClientModRPCHandler("AdventureMode", "UpdateAdventurePresentationWait", function(presentation_id, ready, total)
    if type(presentation_id) ~= "string" or presentation_id == "" or
        type(ready) ~= "number" or type(total) ~= "number" then
        return
    end

    if TheFrontEnd ~= nil then
        TheFrontEnd:UpdateAdventurePresentationWait(presentation_id, ready, total)
    end
end)

AddClientModRPCHandler("AdventureMode", "StopMaxwellIntro", function(presentation_id, guid)
    if type(presentation_id) ~= "string" or presentation_id == "" or type(guid) ~= "number" then
        return
    end

    if TheFrontEnd ~= nil then
        TheFrontEnd:StopMaxwellIntroCutscene(presentation_id, guid)
    end
end)

AddClientModRPCHandler("AdventureMode", "AbortAdventurePresentation", function(presentation_id)
    if type(presentation_id) ~= "string" or presentation_id == "" then
        return
    end

    if TheFrontEnd ~= nil then
        TheFrontEnd:AbortAdventurePresentation(presentation_id)
    end
end)

local maxwell_throne_cutscene_guid = nil
local MAXWELL_THRONE_CAMERA_HEADING = 0

local function IsMaxwellThroneCutscene(guid)
    if type(guid) ~= "number" then
        return false
    end
    return maxwell_throne_cutscene_guid == nil or maxwell_throne_cutscene_guid == guid
end

local function GetLocalMaxwellThrone(guid)
    local inst = type(guid) == "number" and Ents[guid] or nil
    return inst ~= nil and inst:IsValid() and inst:HasTag("maxwellthrone") and inst or nil
end

local function SetLocalMaxwellThroneCameraController(guid, enabled)
    if type(guid) ~= "number" then
        return
    end

    local inst = GetLocalMaxwellThrone(guid)
    if inst == nil then
        return
    end

    local fn = enabled and inst.StartLocalCameraController or inst.StopLocalCameraController
    if fn ~= nil then
        fn(inst)
    end
end

AddClientModRPCHandler("AdventureMode", "StartMaxwellThroneCameraController", function(guid)
    SetLocalMaxwellThroneCameraController(guid, true)
end)

AddClientModRPCHandler("AdventureMode", "StopMaxwellThroneCameraController", function(guid)
    SetLocalMaxwellThroneCameraController(guid, false)
end)

AddClientModRPCHandler("AdventureMode", "StartMaxwellThroneCutscene", function(guid, x, y, z)
    if type(guid) ~= "number" or type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
        return
    end

    maxwell_throne_cutscene_guid = guid

    local inst = GetLocalMaxwellThrone(guid)
    if inst ~= nil then
        inst:StopLocalCameraController()
    end

    local player = ThePlayer
    if player ~= nil and player:IsValid() then
        if player.components.playercontroller ~= nil then
            player.components.playercontroller:Enable(false)
        end
        if player.HUD ~= nil then
            player.HUD:Hide()
        end
    end

    if TheCamera ~= nil then
        TheCamera:SetHeadingTarget(MAXWELL_THRONE_CAMERA_HEADING)
        TheCamera:Snap()
        TheCamera:CutsceneMode(true)
        TheCamera:SetCustomLocation(Vector3(x, y, z))
        TheCamera:SetGains(0.5, 0.1, 2)
        TheCamera:SetMinDistance(5)
        TheCamera:Shake("FULL", 5, 0.033, 0.1)
    end
end)

AddClientModRPCHandler("AdventureMode", "SetMaxwellThroneCutsceneGains", function(guid, gain1, gain2, gain3)
    if not IsMaxwellThroneCutscene(guid) or type(gain1) ~= "number" or type(gain2) ~= "number" or type(gain3) ~= "number" then
        return
    end

    if TheCamera ~= nil then
        TheCamera:SetGains(gain1, gain2, gain3)
    end
end)

AddClientModRPCHandler("AdventureMode", "ShakeMaxwellThroneCutscene", function(guid, duration)
    if not IsMaxwellThroneCutscene(guid) or type(duration) ~= "number" then
        return
    end

    if TheCamera ~= nil then
        TheCamera:Shake("FULL", duration, 0.033, 0.1)
    end
end)

AddClientModRPCHandler("AdventureMode", "ZoomMaxwellThroneCutscene", function(guid, is_maxwell)
    if not IsMaxwellThroneCutscene(guid) then
        return
    end

    if TheCamera ~= nil then
        if not is_maxwell then
            TheCamera:SetOffset(Vector3(0, 1.45, 0))
        end
        TheCamera:SetDistance(7)
    end
end)

AddClientModRPCHandler("AdventureMode", "FadeOutMaxwellThroneCutscene", function(guid, time)
    if not IsMaxwellThroneCutscene(guid) or type(time) ~= "number" then
        return
    end

    if TheFrontEnd ~= nil then
        TheFrontEnd:Fade(false, time)
    end
end)

AddClientModRPCHandler("AdventureMode", "FadeInMaxwellThroneCutscene", function(guid, time)
    if not IsMaxwellThroneCutscene(guid) or type(time) ~= "number" then
        return
    end

    maxwell_throne_cutscene_guid = nil

    if TheFrontEnd ~= nil then
        TheFrontEnd:DoFadeIn(time)
    end
end)

AddClientModRPCHandler("AdventureMode", "ShowMaxwellThroneEndGameDialog", function(guid, character)
    if not IsMaxwellThroneCutscene(guid) or type(character) ~= "string" or character == "" then
        return
    end

    maxwell_throne_cutscene_guid = nil

    if TheFrontEnd ~= nil then
        TheFrontEnd:DoFadeIn(0)
        TheFrontEnd:PushScreen(EndGameDialog({
            {
                text = STRINGS.UI.ENDGAME.YES,
                cb = function()
                    SendModRPCToServer(GetModRPC("AdventureMode", "ConfirmMaxwellThroneEndGameDialog"), guid)
                end,
            },
        }, character))
    end
end)

local function IsMasterShardID(shardid)
    if shardid == nil then
        return false
    end
    shardid = tostring(shardid)
    return shardid == tostring(SHARDID.MASTER) or shardid == "Master"
end

local function IsMasterShardRuntime()
    return ShardWorldIndex ~= nil and ShardWorldIndex:IsMasterShard()
end

local function IsSecondaryRequestFromMaster(shardid)
    return not IsMasterShardRuntime() and IsMasterShardID(shardid)
end

local function IsMasterRequestFromSecondary(shardid)
    return IsMasterShardRuntime() and shardid ~= nil and not IsMasterShardID(shardid)
end

AddShardModRPCHandler("AdventureMode", "ForcePlayersToMaster", function(shardid)
    if not IsSecondaryRequestFromMaster(shardid) then
        return
    end
    ShardWorldIndex:ForceLocalPlayersToMaster()
end)

local function DecodeShardPayload(data)
    if data == nil then
        return {}
    end
    data = DecodeAndUnzipString(data)
    return type(data) == "table" and data or {}
end

local function GetShardGameWorldIndex()
    if ShardGameIndex == nil then
        return nil
    end
    return ShardGameIndex.worldindex
end

local function GetRuntimeSessionID()
    local session_id = TheWorld ~= nil and TheWorld.meta ~= nil and
        TheWorld.meta.session_identifier or nil
    return type(session_id) == "string" and session_id ~= "" and session_id or nil
end

local function GetAdventureTransitionRestartParams(operation)
    if operation == "ReturnSecondaryAdventure" then
        return {}
    end

    local transition = operation == "BeginSecondaryAdventure" and "secondary_begin" or
        operation == "AdvanceSecondaryAdventure" and "secondary_advance" or
        operation == "ResetSecondaryAdventure" and "secondary_reset" or
        "secondary_return"
    return
    {
        world_index_transition = transition,
        world_index_file_id = "adventure",
    }
end

local function RestartSecondaryTransition(worldindex, params, retry_id)
    params = params or {}
    if retry_id ~= nil then
        if type(retry_id) ~= "string" or retry_id == "" then
            print("[Shard World Index] Cannot retry a secondary transition without a request id.")
            return false
        end
        if Settings ~= nil and Settings.secondary_transition_retry_id == retry_id then
            print("[Shard World Index] Secondary transition retry failed for "..retry_id.."; keeping the transaction for a later restart.")
            return false
        end
        params.secondary_transition_retry_id = retry_id
    end

    return worldindex:RestartCurrentSlotAfterShardRPC(params) ~= false
end

local secondary_adventure_operation = nil
local pending_secondary_adventure_sync = nil
local pending_secondary_adventure_sync_task = nil
local ScheduleSecondaryAdventureSync

local function BeginSecondaryAdventureOperation(request_id, phase)
    if type(request_id) ~= "string" or request_id == "" then
        return nil
    end

    local operation = secondary_adventure_operation
    if operation == nil then
        operation =
        {
            kind = "transition",
            request_id = request_id,
        }
        secondary_adventure_operation = operation
    elseif operation.kind ~= "transition" or operation.request_id ~= request_id or operation.running then
        return nil
    end

    operation.phase = phase
    operation.running = true
    return operation
end

local function FinishSecondaryAdventureOperation(operation, retain, resume_sync)
    if secondary_adventure_operation ~= operation then
        return
    end

    operation.running = false
    if retain then
        if pending_secondary_adventure_sync ~= nil and ScheduleSecondaryAdventureSync ~= nil then
            ScheduleSecondaryAdventureSync()
        end
        return
    end

    secondary_adventure_operation = nil
    if resume_sync ~= false and ScheduleSecondaryAdventureSync ~= nil then
        ScheduleSecondaryAdventureSync()
    end
end

ScheduleSecondaryAdventureSync = function(data)
    if data ~= nil then
        pending_secondary_adventure_sync = data
    end
    if pending_secondary_adventure_sync == nil or
        pending_secondary_adventure_sync_task ~= nil then
        return
    end

    local current_operation = secondary_adventure_operation
    if current_operation ~= nil then
        if current_operation.kind == "transition" and not current_operation.running then
            secondary_adventure_operation = nil
        else
            return
        end
    end

    local operation = { kind = "sync", phase = "queued", running = true }
    secondary_adventure_operation = operation

    local function synchronize()
        pending_secondary_adventure_sync_task = nil
        if secondary_adventure_operation ~= operation then
            return
        end

        local worldindex = GetShardGameWorldIndex()
        local adventure = ShardGameIndex ~= nil and ShardGameIndex.adventure or nil
        if adventure == nil or worldindex == nil then
            pending_secondary_adventure_sync = nil
            FinishSecondaryAdventureOperation(operation, false, false)
            return
        end

        local sync_data = pending_secondary_adventure_sync
        pending_secondary_adventure_sync = nil
        operation.phase = "sync"
        adventure:SynchronizeSecondary(sync_data, function(success, changed, retry_id)
            if secondary_adventure_operation ~= operation then
                return
            end

            if changed then
                local restarting = RestartSecondaryTransition(
                    worldindex,
                    {
                        world_index_transition = "secondary_resync",
                        world_index_file_id = "adventure",
                    },
                    success and nil or retry_id
                )
                if restarting then
                    pending_secondary_adventure_sync = nil
                    FinishSecondaryAdventureOperation(operation, false, false)
                else
                    FinishSecondaryAdventureOperation(operation, true, false)
                end
                return
            end

            if not success then
                print("[Adventure Mode] Failed to synchronize the secondary adventure state.")
            end
            FinishSecondaryAdventureOperation(operation, false, true)
        end)
    end

    if TheWorld ~= nil then
        pending_secondary_adventure_sync_task = TheWorld:DoStaticTaskInTime(0, synchronize)
    else
        synchronize()
    end
end

local function ReplySecondaryAdventureRequest(worldindex, shardid, opts, operation, phase, success, file_id)
    if opts.request_id == nil then
        print("[Shard World Index] Missing request id for "..tostring(operation)..".")
        return
    end

    local function reply()
        worldindex:SendShardRPC("AdventureMode", "SecondaryWorldIndexReply", shardid, {
            request_id = opts.request_id,
            operation = operation,
            phase = phase,
            success = success == true,
            file_id = file_id,
        })
    end

    if TheWorld ~= nil then
        TheWorld:DoStaticTaskInTime(0, reply)
    else
        reply()
    end
end

local function AddSecondaryAdventurePrepareHandler(operation)
    AddShardModRPCHandler("AdventureMode", operation, function(shardid, data)
        if not IsSecondaryRequestFromMaster(shardid) then
            return
        end

        local worldindex = GetShardGameWorldIndex()
        if worldindex == nil then
            return
        end

        local opts = DecodeShardPayload(data)
        local adventure = ShardGameIndex ~= nil and ShardGameIndex.adventure or nil
        if adventure ~= nil and adventure:IsSynchronizingSecondary() then
            ReplySecondaryAdventureRequest(worldindex, shardid, opts, operation, "prepare", false)
            return
        end
        local secondary_operation = BeginSecondaryAdventureOperation(opts.request_id, "prepare")
        if secondary_operation == nil then
            ReplySecondaryAdventureRequest(worldindex, shardid, opts, operation, "prepare", false)
            return
        end
        worldindex:PrepareSecondaryTransition(operation, opts, function(success, file_id)
            ReplySecondaryAdventureRequest(worldindex, shardid, opts, operation, "prepare", success, file_id)
            FinishSecondaryAdventureOperation(secondary_operation, success == true, true)
        end)
    end)
end

AddSecondaryAdventurePrepareHandler("BeginSecondaryAdventure")
AddSecondaryAdventurePrepareHandler("AdvanceSecondaryAdventure")
AddSecondaryAdventurePrepareHandler("ResetSecondaryAdventure")
AddSecondaryAdventurePrepareHandler("ReturnSecondaryAdventure")

AddShardModRPCHandler("AdventureMode", "SecondaryWorldIndexReply", function(shardid, data)
    if not IsMasterRequestFromSecondary(shardid) then
        return
    end

    local worldindex = GetShardGameWorldIndex()
    if worldindex ~= nil then
        worldindex:HandleSecondaryWorldIndexReply(shardid, DecodeShardPayload(data))
    end
end)

AddShardModRPCHandler("AdventureMode", "CommitSecondaryWorldIndex", function(shardid, data)
    if not IsSecondaryRequestFromMaster(shardid) then
        return
    end

    local worldindex = GetShardGameWorldIndex()
    if worldindex == nil then
        return
    end

    local opts = DecodeShardPayload(data)
    local secondary_operation = BeginSecondaryAdventureOperation(opts.request_id, "commit")
    if secondary_operation == nil then
        ReplySecondaryAdventureRequest(worldindex, shardid, opts, opts.operation, "commit", false)
        return
    end
    worldindex:CommitPreparedSecondaryTransition(opts.request_id, opts.file_id, function(success, file_id)
        ReplySecondaryAdventureRequest(worldindex, shardid, opts, opts.operation, "commit", success, file_id)
        FinishSecondaryAdventureOperation(secondary_operation, success == true, true)
    end)
end)

AddShardModRPCHandler("AdventureMode", "AbortSecondaryWorldIndex", function(shardid, data)
    if not IsSecondaryRequestFromMaster(shardid) then
        return
    end

    local worldindex = GetShardGameWorldIndex()
    if worldindex == nil then
        return
    end

    local opts = DecodeShardPayload(data)
    local abort_transition
    abort_transition = function()
        local current_operation = secondary_adventure_operation
        if current_operation ~= nil then
            if current_operation.kind == "sync" or
                current_operation.kind == "transition" and current_operation.request_id ~= opts.request_id then
                return
            end
            if current_operation.running then
                if TheWorld ~= nil then
                    TheWorld:DoStaticTaskInTime(0, abort_transition)
                end
                return
            end
        end

        local secondary_operation = BeginSecondaryAdventureOperation(opts.request_id, "abort")
        if secondary_operation == nil then
            return
        end

        worldindex:AbortPreparedSecondaryTransition(opts.request_id, opts.file_id, function(success)
            if not success then
                local restarting = RestartSecondaryTransition(
                    worldindex,
                    GetAdventureTransitionRestartParams(opts.operation),
                    opts.request_id
                )
                FinishSecondaryAdventureOperation(secondary_operation, not restarting, false)
                return
            end

            local running_session_id = GetRuntimeSessionID()
            local indexed_session_id = ShardGameIndex ~= nil and ShardGameIndex:GetSession() or nil
            local restart_required = running_session_id ~= nil and indexed_session_id ~= nil and
                running_session_id ~= indexed_session_id
            if restart_required then
                RestartSecondaryTransition(worldindex, GetAdventureTransitionRestartParams(opts.operation))
            end
            FinishSecondaryAdventureOperation(secondary_operation, false, not restart_required)
        end)
    end
    abort_transition()
end)

AddShardModRPCHandler("AdventureMode", "FinalizeSecondaryWorldIndex", function(shardid, data)
    if not IsSecondaryRequestFromMaster(shardid) then
        return
    end

    local worldindex = GetShardGameWorldIndex()
    if worldindex == nil then
        return
    end

    local opts = DecodeShardPayload(data)
    local secondary_operation = BeginSecondaryAdventureOperation(opts.request_id, "finalize")
    if secondary_operation == nil then
        return
    end
    worldindex:FinalizeSecondaryTransition(opts.request_id, opts.file_id, function(success, committed)
        ReplySecondaryAdventureRequest(
            worldindex,
            shardid,
            opts,
            opts.operation,
            "finalize",
            success == true,
            opts.file_id
        )
        if success and committed then
            RestartSecondaryTransition(worldindex, GetAdventureTransitionRestartParams(opts.operation))
            FinishSecondaryAdventureOperation(secondary_operation, false, false)
        elseif not success then
            local restarting = RestartSecondaryTransition(
                worldindex,
                GetAdventureTransitionRestartParams(opts.operation),
                opts.request_id
            )
            FinishSecondaryAdventureOperation(secondary_operation, not restarting, false)
        else
            FinishSecondaryAdventureOperation(secondary_operation, false, true)
        end
    end)
end)

AddShardModRPCHandler("AdventureMode", "SyncSecondaryAdventure", function(shardid, data)
    if not IsSecondaryRequestFromMaster(shardid) then
        return
    end

    if ShardGameIndex == nil or ShardGameIndex.adventure == nil or GetShardGameWorldIndex() == nil then
        return
    end

    ScheduleSecondaryAdventureSync(DecodeShardPayload(data))
end)

AddShardModRPCHandler("AdventureMode", "ResetAdventureWorldReply", function(shardid, data)
    if not IsSecondaryRequestFromMaster(shardid) or
        ShardGameIndex == nil or ShardGameIndex.adventure == nil then
        return
    end

    local opts = DecodeShardPayload(data)
    ShardGameIndex.adventure:FinishForwardedReset(opts.request_id, opts.success == true)
end)

AddShardModRPCHandler("AdventureMode", "ReturnFromAdventureReply", function(shardid, data)
    if not IsSecondaryRequestFromMaster(shardid) or
        ShardGameIndex == nil or ShardGameIndex.adventure == nil then
        return
    end

    local opts = DecodeShardPayload(data)
    ShardGameIndex.adventure:FinishForwardedReturn(opts.request_id, opts.success == true)
end)

local function IsCurrentAdventureResetRequest(adventure, opts)
    local run = adventure ~= nil and adventure:GetState() or nil
    if run == nil or run.active ~= true then
        return false
    end

    local current_run_id = type(run.run_id) == "string" and run.run_id ~= "" and run.run_id or nil
    local requested_run_id = type(opts.run_id) == "string" and opts.run_id ~= "" and opts.run_id or nil
    return current_run_id == requested_run_id and
        (run.sequence_id or "default") == (opts.sequence_id or "default") and
        math.floor(tonumber(run.chapter) or 0) == math.floor(tonumber(opts.chapter) or -1) and
        math.floor(tonumber(run.chapter_revision) or 1) == math.floor(tonumber(opts.chapter_revision) or 0)
end

local _Shard_OnShardConnected = Shard_OnShardConnected
if type(_Shard_OnShardConnected) == "function" then
    function Shard_OnShardConnected(world_id, ...)
        _Shard_OnShardConnected(world_id, ...)
        if not Shard_IsMaster() or TheWorld == nil then
            return
        end

        local function synchronize()
            if ShardWorldIndex:IsSecondaryWorldIndexRequestPending() then
                TheWorld:DoStaticTaskInTime(1, synchronize)
                return
            end
            if ShardGameIndex ~= nil and ShardGameIndex.adventure ~= nil then
                ShardWorldIndex:SendShardRPC("AdventureMode", "SyncSecondaryAdventure", world_id,
                    ShardGameIndex.adventure:GetSecondarySyncData())
            end
        end
        TheWorld:DoStaticTaskInTime(0, synchronize)
    end
end

AddShardModRPCHandler("AdventureMode", "ResetAdventureWorld", function(shardid, data)
    if not IsMasterRequestFromSecondary(shardid) then
        return
    end

    if ShardGameIndex == nil or ShardGameIndex.adventure == nil then
        return
    end

    local opts = DecodeShardPayload(data)
    if type(opts.request_id) ~= "string" or opts.request_id == "" then
        return
    end
    ShardGameIndex.adventure:EnsureRunID()
    local worldindex = GetShardGameWorldIndex()
    local replied = false
    local function reply(success)
        if replied or worldindex == nil or type(opts.request_id) ~= "string" or opts.request_id == "" then
            return
        end
        replied = true
        local function send_reply()
            worldindex:SendShardRPC("AdventureMode", "ResetAdventureWorldReply", shardid, {
                request_id = opts.request_id,
                success = success == true,
            })
        end
        if TheWorld ~= nil then
            TheWorld:DoStaticTaskInTime(0, send_reply)
        else
            send_reply()
        end
    end
    if not IsCurrentAdventureResetRequest(ShardGameIndex.adventure, opts) then
        reply(false)
        return
    end
    local function reset()
        ShardGameIndex.adventure:ResetCurrentChapterShard(
            { reason = opts.reason or "worldreset" },
            reply
        )
    end
    if TheWorld ~= nil then
        TheWorld:DoTaskInTime(0, reset)
    else
        reset()
    end
end)

AddClientModRPCHandler("AdventureMode", "AdventureReturnResult", function(success)
    if type(success) == "boolean" and TheWorld ~= nil then
        TheWorld:PushEvent("adventure_return_result", { success = success })
    end
end)

AddShardModRPCHandler("AdventureMode", "ReturnFromAdventure", function(shardid, data)
    if not IsMasterRequestFromSecondary(shardid) then
        return
    end

    local opts = DecodeShardPayload(data)
    if type(opts.request_id) ~= "string" or opts.request_id == "" then
        return
    end

    local reason = opts.reason or "return"
    local worldindex = GetShardGameWorldIndex()
    local adventure = ShardGameIndex ~= nil and ShardGameIndex.adventure or nil
    local run = adventure ~= nil and adventure:GetState() or nil
    if run == nil or run.active ~= true or
        run.run_id ~= opts.run_id or
        (run.sequence_id or "default") ~= (opts.sequence_id or "default") then
        if worldindex ~= nil then
            worldindex:SendShardRPC("AdventureMode", "ReturnFromAdventureReply", shardid, {
                request_id = opts.request_id,
                success = false,
            })
        end
        return
    end
    local replied = false
    local function reply(success)
        if replied or worldindex == nil then
            return
        end
        replied = true
        local function send_reply()
            worldindex:SendShardRPC("AdventureMode", "ReturnFromAdventureReply", shardid, {
                request_id = opts.request_id,
                success = success == true,
            })
        end
        if TheWorld ~= nil then
            TheWorld:DoStaticTaskInTime(0, send_reply)
        else
            send_reply()
        end
    end

    if adventure == nil then
        reply(false)
        return
    end

    if TheWorld ~= nil then
        TheWorld:DoTaskInTime(0, function()
            adventure:ReturnFromShard(reason, reply)
        end)
    else
        adventure:ReturnFromShard(reason, reply)
    end
end)

AddModRPCHandler("AdventureMode", "ReturnAfterDeath", function(player)
    if player == nil or not player:IsValid() or player.userid == nil or player.userid == "" then
        return
    end

    local userid = player.userid
    local function reply(success)
        SendModRPCToClient(
            GetClientModRPC("AdventureMode", "AdventureReturnResult"),
            userid,
            success == true
        )
    end
    local client = TheNet:GetClientTableForUser(player.userid)
    if client == nil or not client.admin or ShardGameIndex == nil or ShardGameIndex.adventure == nil or
        not ShardGameIndex.adventure:IsActive() then
        reply(false)
        return
    end

    ShardGameIndex.adventure:ReturnFromShard("death", reply)
end)

AddModRPCHandler("AdventureMode", "Adventure?", function(player, data)
    data = data ~= nil and DecodeAndUnzipString(data) or nil
    if player == nil or not player:IsValid() or
        type(data) ~= "table" or
        type(data.guid) ~= "number" or
        type(data.active) ~= "boolean" then
        return
    end

    local inst = Ents[data.guid]
    if inst == nil or not inst:IsValid() or
        (inst.prefab ~= "adventure_portal" and not inst:HasTag("teleportato")) then
        return
    end

    if inst:HasTag("teleportato") then
        inst:SetPlayerActivation(player, data.active)
    elseif data.active then
        inst:RequestAdventureEntry(player)
    elseif inst.components.activatable ~= nil then
        inst.components.activatable.inactive = true
    end
end)

AddModRPCHandler("AdventureMode", "RequestTeleportatoConfirm", function(player, guid)
    if type(guid) ~= "number" or player == nil or not player:IsValid() then
        return
    end

    local inst = Ents[guid]
    if inst ~= nil and inst:IsValid() and inst:HasTag("teleportato_player_container") then
        inst = inst._base
    end
    if inst == nil or not inst:IsValid() or not inst:HasTag("teleportato") then
        return
    end

    inst:CheckNextLevelSure(player)
end)

AddModRPCHandler("AdventureMode", "UnlockMaxwell", function(player, guid, response)
    if player == nil or not player:IsValid() or
        type(guid) ~= "number" or
        (response ~= "confirm" and response ~= "cancel") then
        return
    end

    local inst = Ents[guid]
    if inst == nil or not inst:IsValid() or not inst:HasTag("maxwelllock") then
        return
    end
    if inst.components.lock == nil then
        return
    end
    if inst._unlocker_userid ~= nil and (player == nil or player.userid ~= inst._unlocker_userid) then
        return
    end

    if response == "confirm" then
        inst:ConfirmUnlock(player)
    else
        inst:CancelUnlock(player)
    end
end)

AddModRPCHandler("AdventureMode", "ConfirmMaxwellThroneEndGameDialog", function(player, guid)
    if player == nil or not player:IsValid() or type(guid) ~= "number" then
        return
    end

    local inst = Ents[guid]
    if inst ~= nil and inst:IsValid() and inst:HasTag("maxwellthrone") then
        inst:ConfirmEndGameDialog(player)
    end
end)

AddModRPCHandler("AdventureMode", "SkipMaxwellIntro", function(player, presentation_id, guid)
    if type(presentation_id) ~= "string" or presentation_id == "" or #presentation_id > 256 or
        type(guid) ~= "number" or player == nil or not player:IsValid() then
        return
    end

    local maxwell_intro = TheWorld ~= nil and TheWorld.components.maxwellintrospawner or nil
    if maxwell_intro ~= nil then
        maxwell_intro:RequestSkip(player, presentation_id, guid)
    end
end)

AddModRPCHandler("AdventureMode", "AdventurePresentationReady", function(player, presentation_id)
    if type(presentation_id) ~= "string" or presentation_id == "" or #presentation_id > 256 then
        return
    end

    local maxwell_intro = TheWorld ~= nil and TheWorld.components.maxwellintrospawner or nil
    local ready = maxwell_intro ~= nil and maxwell_intro:SetPlayerReady(player, presentation_id)
    if not ready and player ~= nil and player.userid ~= nil and player.userid ~= "" then
        SendModRPCToClient(GetClientModRPC("AdventureMode", "AbortAdventurePresentation"), player.userid, presentation_id)
    end
end)

AddModRPCHandler("AdventureMode", "AdventureTitleFinished", function(player, presentation_id)
    if type(presentation_id) ~= "string" or presentation_id == "" or #presentation_id > 256 then
        return
    end

    local maxwell_intro = TheWorld ~= nil and TheWorld.components.maxwellintrospawner or nil
    local finished = maxwell_intro ~= nil and maxwell_intro:SetTitleFinished(player, presentation_id)
    if not finished and player ~= nil and player.userid ~= nil and player.userid ~= "" then
        SendModRPCToClient(GetClientModRPC("AdventureMode", "AbortAdventurePresentation"), player.userid, presentation_id)
    end
end)

local PopupDialogScreen = require "screens/redux/popupdialog"
local BigPopupDialogScreen = require "screens/bigpopupdialog"
AddClientModRPCHandler("AdventureMode", "UnlockMaxwell", function(guid, character)
    if type(guid) ~= "number" or type(character) ~= "string" or character == "" then
        return
    end

    local title = STRINGS.UI.UNLOCKMAXWELL.TITLE or "Unlock Maxwell?"
    local character_name = STRINGS.CHARACTER_NAMES[character] or STRINGS.UI.UNLOCKMAXWELL.THEM or character
    local gender = STRINGS.UI.GENDERSTRINGS[GetGenderStrings(character)] or nil
    local possessive = gender ~= nil and gender.TWO or STRINGS.UI.UNLOCKMAXWELL.THEIR or "their"
    local body = STRINGS.UI.UNLOCKMAXWELL.BODY1..character_name..string.format(STRINGS.UI.UNLOCKMAXWELL.BODY2, possessive)

    local function respond(response)
        SendModRPCToServer(GetModRPC("AdventureMode", "UnlockMaxwell"), guid, response)
        TheFrontEnd:PopScreen()
    end

    local buttons = {
        { text = STRINGS.UI.UNLOCKMAXWELL.YES or STRINGS.UI.YES, cb = function() respond("confirm") end },
        { text = STRINGS.UI.UNLOCKMAXWELL.NO or STRINGS.UI.NO, cb = function() respond("cancel") end },
    }

    TheFrontEnd:PushScreen(PopupDialogScreen(title, body, buttons))
end)

AddClientModRPCHandler("AdventureMode", "Adventure???", function(guid, popup_data)
    if type(guid) ~= "number" then
        return
    end

    popup_data = popup_data ~= nil and DecodeAndUnzipString(popup_data) or nil
    popup_data = type(popup_data) == "table" and popup_data or {}

    local function yes()
        TheFrontEnd:PopScreen()
        SendModRPCToServer(GetModRPC("AdventureMode", "Adventure?"), ZipAndEncodeString({guid = guid, active = true,}))
    end

    local function no()
        TheFrontEnd:PopScreen()
        SendModRPCToServer(GetModRPC("AdventureMode", "Adventure?"), ZipAndEncodeString({guid = guid, active = false,}))
    end

    local buttons = {
        { text = popup_data.yes or STRINGS.UI.STARTADVENTURE.YES, cb = yes },
        { text = popup_data.no or STRINGS.UI.STARTADVENTURE.NO, cb = no },
    }

    -- local Screen = BigPopupDialogScreen(STRINGS.UI.STARTADVENTURE.TITLE, popup_data.body, buttons)
    local Screen = PopupDialogScreen(popup_data.title or STRINGS.UI.STARTADVENTURE.TITLE, popup_data.body, buttons, nil, popup_data.longness or nil, popup_data.style or nil)

    TheFrontEnd:PushScreen(Screen)
end)

AddClientModRPCHandler("AdventureMode", "TeleportatoDenied", function(message)
    if ThePlayer ~= nil and ThePlayer.components.talker ~= nil then
        ThePlayer.components.talker:Say(message or STRINGS.UI.TELEPORTFAIL or "Everyone must stand near the Teleportato.")
    end
end)
