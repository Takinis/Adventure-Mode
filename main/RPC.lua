local AddModRPCHandler = AddModRPCHandler
local AddClientModRPCHandler = AddClientModRPCHandler
GLOBAL.setfenv(1, GLOBAL)

local MAXWELL_INTRO_INPUTS =
{
    CONTROL_PRIMARY,
    CONTROL_SECONDARY,
    CONTROL_ATTACK,
    CONTROL_INSPECT,
    CONTROL_ACTION,
    CONTROL_CONTROLLER_ACTION,
}

local maxwell_intro_state = nil

local function ClearMaxwellIntroInputHandlers()
    if maxwell_intro_state ~= nil and maxwell_intro_state.inputhandlers ~= nil then
        for _, handler in ipairs(maxwell_intro_state.inputhandlers) do
            handler:Remove()
        end
        maxwell_intro_state.inputhandlers = nil
    end
end

local function SendSkipMaxwellIntro()
    if maxwell_intro_state ~= nil and maxwell_intro_state.guid ~= nil then
        SendModRPCToServer(GetModRPC("AdventureMode", "SkipMaxwellIntro"), maxwell_intro_state.guid)
    end
end

local function SetMaxwellIntroCamera(x, y, z)
    local player = ThePlayer
    if player ~= nil and player:IsValid() and TheCamera ~= nil and
        type(x) == "number" and type(y) == "number" and type(z) == "number" then
        local px, py, pz = player.Transform:GetWorldPosition()
        TheCamera:SetOffset((Vector3(x, y, z) - Vector3(px, py, pz)) * .5 + Vector3(0, 2, 0))
        TheCamera:SetDistance(15)
        TheCamera:Snap()
    end
end

local function StartMaxwellIntroCutscene(guid, x, y, z)
    local player = ThePlayer
    if player == nil or not player:IsValid() then
        return
    end

    if maxwell_intro_state == nil then
        maxwell_intro_state =
        {
            inputhandlers = {},
        }
    elseif maxwell_intro_state.inputhandlers == nil then
        maxwell_intro_state.inputhandlers = {}
    end

    if guid ~= nil then
        maxwell_intro_state.guid = guid
    end

    if player.HUD ~= nil then
        player.HUD:Hide()
    end

    if player.components.playercontroller ~= nil then
        player.components.playercontroller:Enable(false)
    end

    if player.sg ~= nil then
        player.sg:GoToState("sleep")
    end

    SetMaxwellIntroCamera(x, y, z)

    if TheInput ~= nil and next(maxwell_intro_state.inputhandlers) == nil then
        for _, control in ipairs(MAXWELL_INTRO_INPUTS) do
            table.insert(maxwell_intro_state.inputhandlers, TheInput:AddControlHandler(control, SendSkipMaxwellIntro))
        end
    end
end

local function StopMaxwellIntroCutscene()
    local player = ThePlayer
    ClearMaxwellIntroInputHandlers()
    maxwell_intro_state = nil

    if player ~= nil and player:IsValid() then
        if player.sg ~= nil and player.sg.currentstate ~= nil and player.sg.currentstate.name == "sleep" then
            player.sg:GoToState("wakeup")
        end

        player:DoTaskInTime(1.5, function()
            if ThePlayer == player and player:IsValid() then
                if player.components.playercontroller ~= nil then
                    player.components.playercontroller:Enable(true)
                end
                if player.HUD ~= nil then
                    player.HUD:Show()
                end
                if TheCamera ~= nil then
                    TheCamera:SetDefault()
                end
            end
        end)
    elseif TheCamera ~= nil then
        TheCamera:SetDefault()
    end
end

function AdventureModeBeginMaxwellIntroCutscene()
    StartMaxwellIntroCutscene(nil)
end

AddClientModRPCHandler("AdventureMode", "ShowTitle", function(level, chapter, play_maxwell_intro)
    if TheFrontEnd ~= nil and TheFrontEnd.QueueAdventureTitle ~= nil then
        TheFrontEnd:QueueAdventureTitle(level, chapter, play_maxwell_intro == true)
    end
end)

AddClientModRPCHandler("AdventureMode", "StartMaxwellIntro", function(guid, x, y, z)
    if type(guid) ~= "number" or type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
        return
    end

    StartMaxwellIntroCutscene(guid, x, y, z)
end)

AddClientModRPCHandler("AdventureMode", "StopMaxwellIntro", function(guid)
    if maxwell_intro_state == nil or guid == nil or maxwell_intro_state.guid == guid then
        StopMaxwellIntroCutscene()
    end
end)

AddShardModRPCHandler("AdventureMode", "ForcePlayersToMaster", function()
    if ShardGameIndex ~= nil and ShardGameIndex.ForceLocalPlayersToMaster ~= nil then
        ShardGameIndex:ForceLocalPlayersToMaster()
    end
end)

AddModRPCHandler("AdventureMode", "Adventure?", function(player, data)
    data = data ~= nil and DecodeAndUnzipString(data) or nil
    if data == nil or type(data.active) ~= "boolean" then
        return
    end

    local inst = data.guid ~= nil and Ents[data.guid] or nil
    if inst == nil or not inst:IsValid() then
        return
    end

    if data.active then
        inst:Adventure(player)
    end
end)

AddModRPCHandler("AdventureMode", "SkipMaxwellIntro", function(player, guid)
    if type(guid) ~= "number" or player == nil then
        return
    end

    local inst = Ents[guid]
    if inst ~= nil and inst:IsValid() and inst.components.maxwelltalker ~= nil then
        inst.components.maxwelltalker:CancelSpeech(player)
    end
end)

AddModRPCHandler("AdventureMode", "RequestMaxwellIntroAfterTitle", function(player)
    local started = player ~= nil and player.StartAdventureMaxwellIntro ~= nil and player:StartAdventureMaxwellIntro()
    if not started and player ~= nil and player.userid ~= nil and player.userid ~= "" then
        SendModRPCToClient(GetClientModRPC("AdventureMode", "StopMaxwellIntro"), player.userid)
    end
end)

local PopupDialogScreen = require "screens/redux/popupdialog"
AddClientModRPCHandler("AdventureMode", "Adventure???", function(inst, popup_data)
    if inst == nil then
        return
    end

    popup_data = popup_data ~= nil and DecodeAndUnzipString(popup_data) or nil
    popup_data = type(popup_data) == "table" and popup_data or {}

    local function yes()
        TheFrontEnd:PopScreen()
        SendModRPCToServer(GetModRPC("AdventureMode", "Adventure?"), ZipAndEncodeString({guid = inst.GUID, active = true,}))
    end

    local function no()
        TheFrontEnd:PopScreen()
        SendModRPCToServer(GetModRPC("AdventureMode", "Adventure?"), ZipAndEncodeString({guid = inst.GUID, active = false,}))
        if popup_data.disable_on_no and inst.components.activatable ~= nil then
            inst.components.activatable.inactive = true
        end
    end

    local buttons = {
        { text = popup_data.yes or STRINGS.UI.STARTADVENTURE.YES, cb = yes },
        { text = popup_data.no or STRINGS.UI.STARTADVENTURE.NO, cb = no },
    }

    local bodytext = popup_data.body or
        ((require("stats").GetTestGroup() == 0 and STRINGS.UI.STARTADVENTURE.BODY) or STRINGS.UI.STARTADVENTURE.BODY_TEST)

    local Screen = PopupDialogScreen(popup_data.title or STRINGS.UI.STARTADVENTURE.TITLE, bodytext, buttons, nil, "big")

    TheFrontEnd:PushScreen(Screen)
end)

AddClientModRPCHandler("AdventureMode", "TeleportatoDenied", function()
    if ThePlayer ~= nil and ThePlayer.components.talker ~= nil then
        ThePlayer.components.talker:Say(STRINGS.UI.TELEPORTFAIL or "Everyone must stand near the Teleportato.")
    end
end)
