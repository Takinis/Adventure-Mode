local AddModRPCHandler = AddModRPCHandler
local AddClientModRPCHandler = AddClientModRPCHandler
local AddShardModRPCHandler = AddShardModRPCHandler
GLOBAL.setfenv(1, GLOBAL)

AddClientModRPCHandler("AdventureMode", "ShowTitle", function(level, chapter, play_maxwell_intro)
    if TheFrontEnd ~= nil and TheFrontEnd.QueueAdventureTitle ~= nil then
        TheFrontEnd:QueueAdventureTitle(level, chapter, play_maxwell_intro == true)
    end
end)

AddClientModRPCHandler("AdventureMode", "StartMaxwellIntro", function(guid, x, y, z)
    if type(guid) ~= "number" or type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
        return
    end

    TheFrontEnd:StartMaxwellIntroCutscene(guid, x, y, z)
end)

AddClientModRPCHandler("AdventureMode", "StopMaxwellIntro", function(guid)
    TheFrontEnd:StopMaxwellIntroCutscene(guid)
end)

AddShardModRPCHandler("AdventureMode", "ForcePlayersToMaster", function()
    ShardGameIndex:ForceLocalPlayersToMaster()
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
