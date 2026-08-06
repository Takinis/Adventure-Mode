require("mathutil")

local assets = {
	Asset("ANIM", "anim/maxwell_throne.zip"),
}

local prefabs = {
    "maxwellendgame",
    "maxwellthrone_puppet",
}

local CUTSCENE_PLAYER_RANGE = 45
local CUTSCENE_PLAYER_RANGE_SQ = CUTSCENE_PLAYER_RANGE * CUTSCENE_PLAYER_RANGE
local PUPPET_SYMBOLS = { "foot", "leg" }

local function AddCutscenePlayer(players, seen, player)
    if player == nil or not player:IsValid() then
        return
    end

    local key = player.userid or player.GUID or player
    if seen[key] then
        return
    end

    seen[key] = true
    table.insert(players, player)
end

local function BuildCutscenePlayers(inst, doer)
    local players = {}
    local seen = {}

    AddCutscenePlayer(players, seen, doer)

    for _, player in ipairs(AllPlayers) do
        if player ~= nil and player:IsValid() and player:GetDistanceSqToInst(inst) <= CUTSCENE_PLAYER_RANGE_SQ then
            AddCutscenePlayer(players, seen, player)
        end
    end

    return players
end

local function ForEachCutscenePlayer(inst, fn)
    local players = inst._maxwellthrone_cutscene_players or {}
    for _, player in ipairs(players) do
        if player ~= nil and player:IsValid() then
            fn(player)
        end
    end
end

local function SendCutsceneRPCToPlayers(inst, rpc_name, ...)
    local rpc = GetClientModRPC("AdventureMode", rpc_name)
    for _, player in ipairs(inst._maxwellthrone_cutscene_players or {}) do
        if player ~= nil and player:IsValid() and player.userid ~= nil and player.userid ~= "" then
            SendModRPCToClient(rpc, player.userid, ...)
        end
    end
end

local function SendCameraControllerRPCToPlayers(inst, rpc_name)
    local rpc = GetClientModRPC("AdventureMode", rpc_name)
    for _, player in ipairs(AllPlayers) do
        if player ~= nil and player:IsValid() and player.userid ~= nil and player.userid ~= "" then
            SendModRPCToClient(rpc, player.userid, inst.GUID)
        end
    end
end

local function GetPlayerCharacter(doer)
    return doer ~= nil and doer.prefab or nil
end

local function GetPlayerBuild(doer, character)
    if doer ~= nil and doer.AnimState ~= nil then
        local build = doer.AnimState:GetBuild()
        if build ~= nil and build ~= "" then
            return build
        end
    end

    return character
end

local function GetPuppetSkins(skins)
    if type(skins) ~= "table" then
        return nil
    end

    local normalized =
    {
        base = type(skins.base) == "string" and skins.base or "",
        body = type(skins.body) == "string" and skins.body or "",
        hand = type(skins.hand) == "string" and skins.hand or "",
        legs = type(skins.legs) == "string" and skins.legs or "",
        feet = type(skins.feet) == "string" and skins.feet or "",
        mode = type(skins.mode) == "string" and skins.mode or "",
        monkey_curse = type(skins.monkey_curse) == "string" and skins.monkey_curse or "",
    }

    if normalized.base == "" and
        normalized.body == "" and
        normalized.hand == "" and
        normalized.legs == "" and
        normalized.feet == "" and
        normalized.mode == "" and
        normalized.monkey_curse == "" then
        return nil
    end

    normalized.mode = normalized.mode ~= "" and normalized.mode or "normal_skin"
    return normalized
end

local function GetPlayerSkins(doer)
    local skinner = doer ~= nil and doer.components.skinner or nil
    if skinner == nil then
        return nil
    end

    local skins = skinner:GetClothing()
    skins.mode = skinner:GetSkinMode()
    skins.monkey_curse = skinner:GetMonkeyCurse()
    return GetPuppetSkins(skins)
end

local function GetPuppetSymbolOverrides(symbols)
    if type(symbols) ~= "table" then
        return nil
    end

    local normalized = {}
    for _, target in ipairs(PUPPET_SYMBOLS) do
        local data = symbols[target]
        if type(data) == "table" then
            local build = type(data.build) == "number" and data.build or
                type(data.build) == "string" and data.build ~= "" and hash(data.build) or nil
            local symbol = type(data.symbol) == "number" and data.symbol or
                type(data.symbol) == "string" and data.symbol ~= "" and hash(data.symbol) or nil
            if build ~= nil and symbol ~= nil then
                normalized[target] =
                {
                    build = build,
                    symbol = symbol,
                    skin = data.skin == true,
                }
            end
        end
    end
    return next(normalized) ~= nil and normalized or nil
end

local function GetPlayerSymbolOverrides(doer)
    if doer == nil or doer.AnimState == nil then
        return nil
    end

    local symbols = {}
    for _, target in ipairs(PUPPET_SYMBOLS) do
        local build, symbol = doer.AnimState:GetSymbolOverride(target)
        if build ~= nil and symbol ~= nil then
            symbols[target] =
            {
                build = build,
                symbol = symbol,
                skin = doer.AnimState:IsSkinBuild(build),
            }
        end
    end
    return GetPuppetSymbolOverrides(symbols)
end

local function GetPuppetRecord(character, build, userid, skins, symbols)
    character = type(character) == "string" and character ~= "" and character or "waxwell"
    build = type(build) == "string" and build ~= "" and build or character

    return
    {
        character = character,
        build = build,
        userid = type(userid) == "string" and userid ~= "" and userid or nil,
        skins = GetPuppetSkins(skins),
        symbols = GetPuppetSymbolOverrides(symbols),
    }
end

local function GetDefaultPuppetRecord()
    local record = ShardGameIndex.adventure:GetMaxwellThronePuppet()
    if record ~= nil then
        return GetPuppetRecord(record.character, record.build, record.userid, record.skins, record.symbols)
    end
    return GetPuppetRecord("waxwell", "waxwell")
end

local function SavePuppetRecord(record)
    ShardGameIndex.adventure:SetMaxwellThronePuppet(record)
end

local function GetPuppetNameOverride(character)
    local gender = GetGenderStrings(character)
    if gender == "FEMALE" then
        return "fem_puppet"
    elseif gender == "ROBOT" then
        return "robot_puppet"
    end

    return "male_puppet"
end

local function StopPuppetTalking(puppet, remove_talk_components)
    if puppet.components.maxwelltalker ~= nil then
        puppet.components.maxwelltalker:StopTalking()

        if remove_talk_components then
            puppet:RemoveComponent("maxwelltalker")
        end
    end

    if remove_talk_components and puppet.components.playerprox ~= nil then
        puppet:RemoveComponent("playerprox")
    end

    if remove_talk_components and puppet.components.talkable ~= nil then
        puppet:RemoveComponent("talkable")
    end
end

local function SetPuppetCharacter(puppet, record)
    if puppet.prefab == "maxwellthrone_puppet" then
        puppet:SetPuppetCharacter(record)
    end
end

local function SpawnPuppet(inst, record, remove_talk_components)
    local puppet = record.character == "waxwell" and SpawnPrefab("maxwellendgame") or SpawnPrefab("maxwellthrone_puppet")
    if puppet == nil then
        puppet = SpawnPrefab("maxwellendgame")
    end
    if puppet == nil then
        return nil
    end

    puppet.persists = false
    SetPuppetCharacter(puppet, record)
    StopPuppetTalking(puppet, remove_talk_components)

    local x, y, z = inst.Transform:GetWorldPosition()
    if puppet.Physics ~= nil then
        puppet.Physics:Teleport(x, y + 0.1, z)
    else
        puppet.Transform:SetPosition(x, y + 0.1, z)
        puppet.Transform:ClearTransformationHistory()
    end

    return puppet
end

local function SetThronePuppetState(inst, record)
    local puppet_record = GetPuppetRecord(
        record ~= nil and record.character or nil,
        record ~= nil and record.build or nil,
        record ~= nil and record.userid or nil,
        record ~= nil and record.skins or nil,
        record ~= nil and record.symbols or nil
    )
    local is_maxwell = puppet_record.character == "waxwell"

    inst.isMaxwell = is_maxwell
    if is_maxwell then
        inst.AnimState:PlayAnimation("idle")
    else
        inst.AnimState:PlayAnimation("player_idle_loop", true)
    end

    if inst.puppet ~= nil and inst.puppet:IsValid() then
        inst.puppet:Remove()
        inst.puppet = nil
    end

    inst.puppet = SpawnPuppet(inst, puppet_record, not is_maxwell)
    if inst.puppet ~= nil then
        inst.puppet.AnimState:PlayAnimation(is_maxwell and "idle_loop" or "throne_loop", true)
    end
end

local function ApplyPuppetCharacter(inst)
    if not TheWorld.ismastersim then
        return
    end

    local character = inst._puppet_character:value()
    if character == nil or character == "" then
        character = "wilson"
    end

    local build = inst._puppet_build:value()
    if build == nil or build == "" then
        build = character
    end

    local skins = GetPuppetSkins({
        base = inst._puppet_skin_base:value(),
        body = inst._puppet_skin_body:value(),
        hand = inst._puppet_skin_hand:value(),
        legs = inst._puppet_skin_legs:value(),
        feet = inst._puppet_skin_feet:value(),
        mode = inst._puppet_skin_mode:value(),
        monkey_curse = inst._puppet_monkey_curse:value(),
    })
    if skins ~= nil then
        inst.components.skinner:ApplyAdventureModeCopiedSkins(
            character,
            inst._puppet_userid:value(),
            skins,
            skins.monkey_curse,
            skins.mode,
            build
        )
    else
        inst.AnimState:SetBuild(build)
    end

    for _, target in ipairs(PUPPET_SYMBOLS) do
        local data = inst._puppet_symbols[target]
        local override_build = data.build:value()
        local override_symbol = data.symbol:value()
        if override_build ~= 0 and override_symbol ~= 0 then
            if data.skin:value() then
                inst.AnimState:OverrideSkinSymbol(target, override_build, override_symbol)
            else
                inst.AnimState:OverrideSymbol(target, override_build, override_symbol)
            end
        end
    end

    inst.components.named:SetName(STRINGS.CHARACTER_NAMES[character] or STRINGS.NAMES[string.upper(character)] or character)
    inst.components.inspectable.nameoverride = GetPuppetNameOverride(character)
end

local function maxwellthrone_puppet_fn()
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    MakeObstaclePhysics(inst, 2)
    inst.Transform:SetFourFaced()

    inst._puppet_character = net_string(inst.GUID, "maxwellthrone_puppet._puppet_character")
    inst._puppet_build = net_string(inst.GUID, "maxwellthrone_puppet._puppet_build")
    inst._puppet_userid = net_string(inst.GUID, "maxwellthrone_puppet._puppet_userid")
    inst._puppet_skin_base = net_string(inst.GUID, "maxwellthrone_puppet._puppet_skin_base")
    inst._puppet_skin_body = net_string(inst.GUID, "maxwellthrone_puppet._puppet_skin_body")
    inst._puppet_skin_hand = net_string(inst.GUID, "maxwellthrone_puppet._puppet_skin_hand")
    inst._puppet_skin_legs = net_string(inst.GUID, "maxwellthrone_puppet._puppet_skin_legs")
    inst._puppet_skin_feet = net_string(inst.GUID, "maxwellthrone_puppet._puppet_skin_feet")
    inst._puppet_skin_mode = net_string(inst.GUID, "maxwellthrone_puppet._puppet_skin_mode")
    inst._puppet_monkey_curse = net_string(inst.GUID, "maxwellthrone_puppet._puppet_monkey_curse")
    inst._puppet_symbols = {}
    for _, target in ipairs(PUPPET_SYMBOLS) do
        local name = "maxwellthrone_puppet._puppet_"..target
        inst._puppet_symbols[target] =
        {
            build = net_hash(inst.GUID, name.."_build"),
            symbol = net_hash(inst.GUID, name.."_symbol"),
            skin = net_bool(inst.GUID, name.."_skin"),
        }
    end
    inst.AnimState:SetBank("wilson")
    inst.AnimState:SetBuild("wilson")
    inst.AnimState:PlayAnimation("throne_loop", true)
    inst.AnimState:Hide("ARM_carry")
    inst.AnimState:Show("ARM_normal")

    inst:AddTag("puppet")

    inst.entity:SetPristine()

    inst.SetPuppetCharacter = function(inst, record)
        record = GetPuppetRecord(record.character, record.build, record.userid, record.skins, record.symbols)
        local skins = record.skins or {}
        local symbols = record.symbols or {}

        inst._puppet_character:set(record.character)
        inst._puppet_build:set(record.build)
        inst._puppet_userid:set(record.userid or "")
        inst._puppet_skin_base:set(skins.base or "")
        inst._puppet_skin_body:set(skins.body or "")
        inst._puppet_skin_hand:set(skins.hand or "")
        inst._puppet_skin_legs:set(skins.legs or "")
        inst._puppet_skin_feet:set(skins.feet or "")
        inst._puppet_skin_mode:set(skins.mode or "")
        inst._puppet_monkey_curse:set(skins.monkey_curse or "")
        for _, target in ipairs(PUPPET_SYMBOLS) do
            local data = symbols[target]
            inst._puppet_symbols[target].build:set(data ~= nil and data.build or 0)
            inst._puppet_symbols[target].symbol:set(data ~= nil and data.symbol or 0)
            inst._puppet_symbols[target].skin:set(data ~= nil and data.skin or false)
        end
        ApplyPuppetCharacter(inst)
    end

    if not TheWorld.ismastersim then
        return inst
    end

    inst.persists = false
    inst:AddComponent("named")
    inst:AddComponent("inspectable")
    inst:AddComponent("skinner")
    inst.components.skinner:SetupNonPlayerData()
    ApplyPuppetCharacter(inst)

    return inst
end

local function ReturnToMainWorld(inst)
    if ShardGameIndex == nil or ShardGameIndex.adventure == nil then
        return false
    end

    inst._adventure_return_pending = true
    return ShardGameIndex.adventure:ReturnFromShard("maxwellthrone", function(success)
        if success or not inst:IsValid() then
            return
        end

        inst._adventure_return_pending = nil
        inst._endgame_dialog_players = {}
        ForEachCutscenePlayer(inst, function(player)
            if player.userid ~= nil and player.userid ~= "" then
                inst._endgame_dialog_players[player.userid] = false
            end
        end)
        inst._awaiting_endgame_dialog = next(inst._endgame_dialog_players) ~= nil
        if inst._awaiting_endgame_dialog then
            SendCutsceneRPCToPlayers(inst, "ShowMaxwellThroneEndGameDialog", inst.GUID, inst._replacement_character)
        end
    end)
end

local function TryReturnToMainWorld(inst)
    if inst._adventure_return_pending then
        return false
    end
    for _, confirmed in pairs(inst._endgame_dialog_players or {}) do
        if not confirmed then
            return false
        end
    end

    inst._awaiting_endgame_dialog = nil
    inst._endgame_dialog_players = nil
    return ReturnToMainWorld(inst)
end

local function ConfirmEndGameDialog(inst, player)
    local userid = player ~= nil and player.userid or nil
    if not inst._awaiting_endgame_dialog or userid == nil or
        inst._endgame_dialog_players[userid] ~= false then
        return false
    end

    inst._endgame_dialog_players[userid] = true
    TryReturnToMainWorld(inst)
    return true
end

local function OnPlayerLeft(inst, player)
    local userid = player ~= nil and player.userid or nil
    if not inst._awaiting_endgame_dialog or userid == nil or
        inst._endgame_dialog_players[userid] == nil then
        return
    end

    inst._endgame_dialog_players[userid] = nil
    TryReturnToMainWorld(inst)
end

local function ZoomAndFade(inst)
    SendCutsceneRPCToPlayers(inst, "ZoomMaxwellThroneCutscene", inst.GUID, inst.isMaxwell == true)

    Sleep(2)

    if inst.phonograph ~= nil and inst.phonograph:IsValid() then
        inst.phonograph.songToPlay = "dontstarve/maxwell/ragtime_2d"
        if inst.phonograph.components.machine ~= nil and not inst.phonograph.components.machine:IsOn() then
            inst.phonograph.components.machine:TurnOn()
        end
    end

    Sleep(5)

    SendCutsceneRPCToPlayers(inst, "FadeOutMaxwellThroneCutscene", inst.GUID, 3)

    Sleep(4)

    inst._endgame_dialog_players = {}
    ForEachCutscenePlayer(inst, function(player)
        if player.userid ~= nil and player.userid ~= "" then
            inst._endgame_dialog_players[player.userid] = false
        end
    end)
    inst._awaiting_endgame_dialog = true
    SendCutsceneRPCToPlayers(inst, "ShowMaxwellThroneEndGameDialog", inst.GUID, inst._replacement_character)
    TryReturnToMainWorld(inst)
end

local function DecomposePuppet(inst)
    if inst.puppet == nil or not inst.puppet:IsValid() then
        return
    end

    local tick_time = TheSim:GetTickTime()
    local time_to_erode = 4
    local puppet = inst.puppet

    puppet:StartThread(function()
        local ticks = 0
        while puppet:IsValid() and ticks * tick_time < time_to_erode do
            local erode_amount = ticks * tick_time / time_to_erode
            puppet.AnimState:SetErosionParams(erode_amount, 0.1, 1.0)
            ticks = ticks + 1
            Yield()
        end

        if puppet:IsValid() then
            puppet:Remove()
        end
    end)
end

local function SpawnNewPuppet(inst)
    inst.SoundEmitter:PlaySound("dontstarve/common/throne/thronemagic", "deathrattle")
    DecomposePuppet(inst)

    SendCutsceneRPCToPlayers(inst, "ShakeMaxwellThroneCutscene", inst.GUID, 4)

    ForEachCutscenePlayer(inst, function(player)
        if player.sg ~= nil then
            player.sg:GoToState("teleportato_teleport")
        end
        if player.DynamicShadow ~= nil then
            player.DynamicShadow:Enable(false)
        end
    end)

    Sleep(4)

    inst.SoundEmitter:KillSound("deathrattle")

    ForEachCutscenePlayer(inst, function(player)
        player:Hide()
    end)

    local puppet_to_spawn = inst._replacement_character
    local puppet_build = inst._replacement_build or puppet_to_spawn
    local puppet_record = GetPuppetRecord(
        puppet_to_spawn,
        puppet_build,
        inst._replacement_userid,
        inst._replacement_skins,
        inst._replacement_symbols
    )
    local new_is_maxwell = puppet_record.character == "waxwell"

    SavePuppetRecord(puppet_record)

    local puppet = SpawnPuppet(inst, puppet_record, true)
    inst.puppet = puppet

    local pos = inst:GetPosition()
    TheWorld:PushEvent("ms_sendlightningstrike", pos)

    if new_is_maxwell then
        inst.AnimState:PlayAnimation("appear")
        inst.AnimState:PushAnimation("idle")
        inst.isMaxwell = true
    else
        inst.AnimState:PlayAnimation("player_appear")
        inst.AnimState:PushAnimation("player_idle_loop", true)
        inst.isMaxwell = false
    end

    if puppet ~= nil then
        if new_is_maxwell then
            puppet.AnimState:PlayAnimation("appear")
            puppet.AnimState:PushAnimation("idle_loop", true)
        else
            puppet.AnimState:PlayAnimation("appear")
            puppet.AnimState:PushAnimation("throne_loop", true)
        end
    end

    if inst.DynamicShadow ~= nil then
        inst.DynamicShadow:Enable(true)
    end

    Sleep(2 * FRAMES)

    inst.SoundEmitter:PlaySound("dontstarve/common/throne/playerappear")

    Sleep(3)

    inst:StartThread(function()
        ZoomAndFade(inst)
    end)
end

local function MaxwellDie(inst)
    inst.AnimState:PlayAnimation("death")

    if inst.puppet ~= nil and inst.puppet:IsValid() then
        inst.puppet.AnimState:PlayAnimation("death")
    end

    inst.SoundEmitter:PlaySound("dontstarve/maxwell/breakchains")
    inst:DoTaskInTime(113 * FRAMES, function()
        if inst:IsValid() then
            inst.SoundEmitter:PlaySound("dontstarve/maxwell/blowsaway")
        end
    end)
    inst:DoTaskInTime(95 * FRAMES, function()
        if inst:IsValid() then
            inst.SoundEmitter:PlaySound("dontstarve/maxwell/throne_scream")
        end
    end)
    inst:DoTaskInTime(213 * FRAMES, function()
        if inst:IsValid() then
            inst.SoundEmitter:KillSound("deathrattle")
        end
    end)

    Sleep(9.5)

    if inst:IsValid() then
        inst:StartThread(function()
            SpawnNewPuppet(inst)
        end)
    end
end

local function PlayerDie(inst)
    inst.AnimState:PlayAnimation("player_death")

    if inst.puppet ~= nil and inst.puppet:IsValid() then
        inst.puppet.AnimState:PlayAnimation("death")
    end

    inst:DoTaskInTime(24 * FRAMES, function()
        if inst:IsValid() then
            inst.SoundEmitter:PlaySound("dontstarve/wilson/death")
        end
    end)
    inst:DoTaskInTime(40 * FRAMES, function()
        if inst:IsValid() then
            inst.SoundEmitter:KillSound("deathrattle")
        end
    end)

    Sleep(4)

    if inst:IsValid() then
        inst:StartThread(function()
            SpawnNewPuppet(inst)
        end)
    end
end

local function SetUpCutscene(inst, doer, replacement)
    if inst.puppet ~= nil and inst.puppet:IsValid() then
        StopPuppetTalking(inst.puppet, true)
        inst.puppet.AnimState:PlayAnimation(inst.isMaxwell and "idle_loop" or "throne_loop")
    end

    replacement = replacement or {}
    local character = replacement.character or GetPlayerCharacter(doer)
    local puppet_record = GetPuppetRecord(
        character,
        replacement.build or GetPlayerBuild(doer, character),
        replacement.userid or (doer ~= nil and doer.userid or nil),
        replacement.skins or GetPlayerSkins(doer),
        replacement.symbols or GetPlayerSymbolOverrides(doer)
    )
    inst._replacement_character = puppet_record.character
    inst._replacement_build = puppet_record.build
    inst._replacement_userid = puppet_record.userid
    inst._replacement_skins = puppet_record.skins
    inst._replacement_symbols = puppet_record.symbols
    inst._maxwellthrone_cutscene_players = BuildCutscenePlayers(inst, doer)

    local pt = inst:GetPosition()
    ForEachCutscenePlayer(inst, function(player)
        player:ForceFacePoint(pt.x, pt.y, pt.z)
    end)

    SendCutsceneRPCToPlayers(inst, "StartMaxwellThroneCutscene", inst.GUID, pt.x, pt.y, pt.z)

    inst.phonograph = TheSim:FindFirstEntityWithTag("maxwellphonograph")
    if inst.phonograph ~= nil and inst.phonograph.components.machine ~= nil and inst.phonograph.components.machine:IsOn() then
        inst.phonograph.components.machine:TurnOff()
    end

    inst.SoundEmitter:PlaySound("dontstarve/common/throne/thronemagic", "deathrattle")

    Sleep(3)

    SendCutsceneRPCToPlayers(inst, "SetMaxwellThroneCutsceneGains", inst.GUID, 0.5, 0.1, 0.3)

    Sleep(2)

    if inst.DynamicShadow ~= nil then
        inst.DynamicShadow:Enable(false)
    end

    inst.SoundEmitter:PlaySound("dontstarve/common/throne/thronedisappear")

    if inst.isMaxwell then
        inst:StartThread(function()
            MaxwellDie(inst)
        end)
    else
        inst:StartThread(function()
            PlayerDie(inst)
        end)
    end
end

local function StartEndGameSequence(inst, doer, replacement)
    if inst._endgame_started then
        return false
    end

    inst._endgame_started = true
    inst._endgame_cutscene_active:set(true)
    inst.task = inst:StartThread(function()
        SetUpCutscene(inst, doer, replacement)
    end)

    return true
end

local DIST_TO_START = CUTSCENE_PLAYER_RANGE
local DIST_TO_START_SQ = CUTSCENE_PLAYER_RANGE_SQ
local DIST_TO_FINISH = 35
local DIST_TO_FINISH_SQ = DIST_TO_FINISH * DIST_TO_FINISH
local DIST_TO_LERP_OVER = DIST_TO_START_SQ - DIST_TO_FINISH_SQ

local STARTING_CAMERA_OFFSET = 1.5
local FINAL_CAMERA_OFFSET = 3

local UPDATE_PERIOD = 0.05

local active_inst = nil

local function RoundToNearest(num, multiple)
    local half = multiple / 2
    return num + half - (num + half) % multiple
end

local function IsLocalCameraReady(inst)
    return TheNet ~= nil
        and not TheNet:IsDedicated()
        and TheCamera ~= nil
        and ThePlayer ~= nil
        and ThePlayer:IsValid()
        and not inst._endgame_cutscene_active:value()
end

local function RestoreCamera(inst)
    if inst._camera_maxwellthrone_active then
        local state = inst._camera_maxwellthrone_state

        if state ~= nil and TheCamera ~= nil then
            if state.prev_offset ~= nil then
                TheCamera:SetOffset(state.prev_offset)
            end
            if state.prev_dist ~= nil then
                TheCamera:SetDistance(state.prev_dist)
            end
            if state.prev_angle ~= nil then
                TheCamera:SetHeadingTarget(state.prev_angle)
            end
            TheCamera:Apply()

            if state.prev_controllable ~= nil then
                TheCamera:SetControllable(state.prev_controllable)
            else
                TheCamera:SetControllable(true)
            end
        end
    end

    if active_inst == inst then
        active_inst = nil
    end

    inst._camera_maxwellthrone_active = nil
    inst._camera_maxwellthrone_state = nil
end

local function BeginCamera(inst)
    if active_inst ~= nil and active_inst ~= inst then
        if active_inst:IsValid() then
            return false
        end
        active_inst = nil
    end

    local ox, oy, oz = TheCamera.targetoffset:Get()

    inst._camera_maxwellthrone_state =
    {
        prev_angle = TheCamera:GetHeadingTarget(),
        prev_dist = TheCamera:GetDistance(),
        prev_offset = Vector3(ox, oy, oz),
        prev_controllable = TheCamera:IsControllable(),
    }
    inst._camera_maxwellthrone_active = true
    active_inst = inst

    return true
end

local function UpdateCamera(inst)
    if not IsLocalCameraReady(inst) then
        RestoreCamera(inst)
        return
    end

    local dist_to_target = ThePlayer:GetDistanceSqToInst(inst)

    if dist_to_target >= DIST_TO_START_SQ then
        RestoreCamera(inst)
        return
    end

    if not inst._camera_maxwellthrone_active and not BeginCamera(inst) then
        return
    end

    local state = inst._camera_maxwellthrone_state
    if state == nil then
        return
    end

    TheCamera:SetControllable(false)

    local percent_from_player = (dist_to_target - DIST_TO_FINISH_SQ) / DIST_TO_LERP_OVER
    local final_angle = RoundToNearest(state.prev_angle, 360)

    if percent_from_player >= 0 and percent_from_player <= 1 then
        local cam_angle = Lerp(final_angle, state.prev_angle, percent_from_player)
        local cam_dist = Lerp(20, state.prev_dist, percent_from_player)

        TheCamera:SetOffset(Vector3(0, Lerp(FINAL_CAMERA_OFFSET, STARTING_CAMERA_OFFSET, percent_from_player), 0))
        TheCamera:SetDistance(cam_dist)
        TheCamera:SetHeadingTarget(cam_angle)
        TheCamera:Apply()
    elseif percent_from_player < 0 and TheCamera:GetHeadingTarget() ~= final_angle then
        TheCamera:SetOffset(Vector3(0, FINAL_CAMERA_OFFSET, 0))
        TheCamera:SetDistance(20)
        TheCamera:SetHeadingTarget(final_angle)
        TheCamera:Apply()
    end
end

local function StopLocalCameraController(inst)
    if inst._camera_maxwellthrone_task ~= nil then
        inst._camera_maxwellthrone_task:Cancel()
        inst._camera_maxwellthrone_task = nil
    end

    RestoreCamera(inst)
end

local function StartLocalCameraController(inst)
    if TheNet ~= nil and TheNet:IsDedicated() then
        return
    end

    if inst._camera_maxwellthrone_task == nil then
        inst._camera_maxwellthrone_task = inst:DoPeriodicTask(UPDATE_PERIOD, UpdateCamera)
        inst:ListenForEvent("onremove", StopLocalCameraController)
    end
end

local function StopCameraController(inst)
    StopLocalCameraController(inst)

    if TheWorld ~= nil and TheWorld.ismastersim then
        SendCameraControllerRPCToPlayers(inst, "StopMaxwellThroneCameraController")
    end
end

local function StartCameraController(inst)
    StartLocalCameraController(inst)

    if TheWorld ~= nil and TheWorld.ismastersim then
        SendCameraControllerRPCToPlayers(inst, "StartMaxwellThroneCameraController")
    end
end

local function fn()
    local inst = CreateEntity()
	inst.entity:AddTransform()
	inst.entity:AddAnimState()
	inst.entity:AddSoundEmitter()
    inst.entity:AddDynamicShadow()
	inst.entity:AddNetwork()

    inst._endgame_cutscene_active = net_bool(inst.GUID, "maxwellthrone._endgame_cutscene_active")

	inst.DynamicShadow:SetSize(3, 2)

    inst.AnimState:SetBank("throne")
    inst.AnimState:SetBuild("maxwell_throne")
    inst.AnimState:PlayAnimation("idle")

    inst:AddTag("maxwellthrone")

    inst.entity:SetPristine()

    inst.StartCameraController = StartCameraController
    inst.StopCameraController = StopCameraController
    inst.StartLocalCameraController = StartLocalCameraController
    inst.StopLocalCameraController = StopLocalCameraController
    StartCameraController(inst)

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("inspectable")

    inst.isMaxwell = true
    inst.StartEndGameSequence = StartEndGameSequence
    inst.ConfirmEndGameDialog = ConfirmEndGameDialog
    inst:ListenForEvent("ms_playerleft", OnPlayerLeft, TheWorld)

    inst:DoTaskInTime(0, function()
        if inst:IsValid() then
            SetThronePuppetState(inst, GetDefaultPuppetRecord())
        end
    end)

    return inst
end

return Prefab("maxwellthrone_puppet", maxwellthrone_puppet_fn, {
        Asset("ANIM", "anim/player_basic.zip"),
        Asset("ANIM", "anim/player_throne.zip"),
        Asset("ANIM", "anim/dynamic/wilson.zip"),
    }),
    Prefab("maxwellthrone", fn, assets, prefabs)
