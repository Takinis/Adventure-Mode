local AddModRPCHandler = AddModRPCHandler
local AddClientModRPCHandler = AddClientModRPCHandler
local AddShardModRPCHandler = AddShardModRPCHandler
GLOBAL.setfenv(1, GLOBAL)

AddClientModRPCHandler("AdventureMode", "ShowTitle", function(level, chapter, play_maxwell_intro)
    if TheFrontEnd ~= nil then
        TheFrontEnd:QueueAdventureTitle(level, chapter, play_maxwell_intro == true)
    end
end)

AddClientModRPCHandler("AdventureMode", "StartMaxwellIntro", function(guid, x, y, z)
    if type(guid) ~= "number" or type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
        return
    end

    if TheFrontEnd ~= nil then
        TheFrontEnd:StartMaxwellIntroCutscene(guid, x, y, z)
    end
end)

AddClientModRPCHandler("AdventureMode", "StopMaxwellIntro", function(guid)
    if guid ~= nil and type(guid) ~= "number" then
        return
    end

    if TheFrontEnd ~= nil then
        TheFrontEnd:StopMaxwellIntroCutscene(guid)
    end
end)

local maxwell_throne_cutscene_guid = nil

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

AddShardModRPCHandler("AdventureMode", "ForcePlayersToMaster", function()
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

AddShardModRPCHandler("AdventureMode", "BeginSecondaryAdventure", function(_, data)
    local worldindex = GetShardGameWorldIndex()
    if ShardGameIndex == nil or ShardGameIndex.adventure == nil or worldindex == nil then
        return
    end

    local opts = DecodeShardPayload(data)
    ShardGameIndex.adventure:BeginSecondary(opts, function(success)
        if success then
            worldindex:RestartCurrentSlotAfterShardRPC({ adventure_transition = "secondary_begin" })
        end
    end)
end)

AddShardModRPCHandler("AdventureMode", "AdvanceSecondaryAdventure", function(_, data)
    local worldindex = GetShardGameWorldIndex()
    if ShardGameIndex == nil or ShardGameIndex.adventure == nil or worldindex == nil then
        return
    end

    local opts = DecodeShardPayload(data)
    ShardGameIndex.adventure:AdvanceSecondary(opts, function(success)
        if success then
            worldindex:RestartCurrentSlotAfterShardRPC({ adventure_transition = "secondary_advance" })
        end
    end)
end)

AddShardModRPCHandler("AdventureMode", "ReturnSecondaryAdventure", function(_, data)
    local worldindex = GetShardGameWorldIndex()
    if ShardGameIndex == nil or ShardGameIndex.adventure == nil or worldindex == nil then
        return
    end

    local opts = DecodeShardPayload(data)
    ShardGameIndex.adventure:ReturnToMainWorld(opts.reason or "return", function(success)
        if success then
            worldindex:RestartCurrentSlotAfterShardRPC({ adventure_transition = opts.reason or "secondary_return" })
        end
    end)
end)

AddShardModRPCHandler("AdventureMode", "ReturnFromAdventure", function(_, data)
    if ShardGameIndex == nil or ShardGameIndex.adventure == nil then
        return
    end

    local opts = DecodeShardPayload(data)
    local reason = opts.reason or "return"
    if TheWorld ~= nil then
        TheWorld:DoTaskInTime(0, function()
            ShardGameIndex.adventure:ReturnFromShard(reason)
        end)
    else
        ShardGameIndex.adventure:ReturnFromShard(reason)
    end
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
        (inst.prefab ~= "adventure_portal" and inst.prefab ~= "teleportato") then
        return
    end

    if data.active then
        inst:Adventure(player)
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

AddModRPCHandler("AdventureMode", "UnlockMaxwell", function(player, guid, accepted)
    if player == nil or not player:IsValid() or
        type(guid) ~= "number" or
        type(accepted) ~= "boolean" then
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

    if accepted then
        if inst.components.lock:IsLocked() then
            return
        end
        inst:ConfirmUnlock(player)
    else
        inst:CancelUnlock(player)
    end
end)

AddModRPCHandler("AdventureMode", "SkipMaxwellIntro", function(player, guid)
    if type(guid) ~= "number" or player == nil or not player:IsValid() then
        return
    end

    local inst = Ents[guid]
    if inst ~= nil and inst:IsValid() and inst.prefab == "maxwellintro" and
        inst.components.maxwelltalker ~= nil then
        inst.components.maxwelltalker:CancelSpeech(player)
    end
end)

AddModRPCHandler("AdventureMode", "RequestMaxwellIntroAfterTitle", function(player)
    local maxwell_intro = player ~= nil and player.components ~= nil and player.components.maxwellintrospawner or nil
    local started = maxwell_intro ~= nil and maxwell_intro:StartCurrentChapter()
    if not started and player ~= nil and player.userid ~= nil and player.userid ~= "" then
        SendModRPCToClient(GetClientModRPC("AdventureMode", "StopMaxwellIntro"), player.userid)
    end
end)

local PopupDialogScreen = require "screens/redux/popupdialog"
local BigPopupDialogScreen = require "screens/bigpopupdialog"
AddClientModRPCHandler("AdventureMode", "UnlockMaxwell", function(guid)
    if type(guid) ~= "number" then
        return
    end

    local character = ThePlayer ~= nil and ThePlayer.prefab or "wilson"
    local title = STRINGS.UI.UNLOCKMAXWELL ~= nil and STRINGS.UI.UNLOCKMAXWELL.TITLE or "Unlock Maxwell?"
    local body

    if STRINGS.UI.UNLOCKMAXWELL ~= nil and
        STRINGS.UI.UNLOCKMAXWELL.BODY1 ~= nil and
        STRINGS.UI.UNLOCKMAXWELL.BODY2 ~= nil then
        local character_name = STRINGS.CHARACTER_NAMES ~= nil and STRINGS.CHARACTER_NAMES[character] or STRINGS.UI.UNLOCKMAXWELL.THEM or character
        local gender = GetGenderStrings ~= nil and STRINGS.UI.GENDERSTRINGS ~= nil and STRINGS.UI.GENDERSTRINGS[GetGenderStrings(character)] or nil
        local possessive = gender ~= nil and gender.TWO or STRINGS.UI.UNLOCKMAXWELL.THEIR or "their"
        body = STRINGS.UI.UNLOCKMAXWELL.BODY1..character_name..string.format(STRINGS.UI.UNLOCKMAXWELL.BODY2, possessive)
    else
        body = "Free Maxwell from the throne?"
    end

    local function respond(accepted)
        TheFrontEnd:PopScreen()
        SendModRPCToServer(GetModRPC("AdventureMode", "UnlockMaxwell"), guid, accepted)
    end

    local buttons = {
        { text = STRINGS.UI.UNLOCKMAXWELL ~= nil and STRINGS.UI.UNLOCKMAXWELL.YES or STRINGS.UI.YES, cb = function() respond(true) end },
        { text = STRINGS.UI.UNLOCKMAXWELL ~= nil and STRINGS.UI.UNLOCKMAXWELL.NO or STRINGS.UI.NO, cb = function() respond(false) end },
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
    local Screen = PopupDialogScreen(popup_data.title or STRINGS.UI.STARTADVENTURE.TITLE, popup_data.body, buttons, nil, "big", "dark_wide")

    TheFrontEnd:PushScreen(Screen)
end)

AddClientModRPCHandler("AdventureMode", "TeleportatoDenied", function(message)
    if ThePlayer ~= nil and ThePlayer.components.talker ~= nil then
        ThePlayer.components.talker:Say(message or STRINGS.UI.TELEPORTFAIL or "Everyone must stand near the Teleportato.")
    end
end)
