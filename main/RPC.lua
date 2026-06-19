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
        inst.components.activatable.inactive = true
    end

    local buttons = {
        { text = popup_data.yes or STRINGS.UI.STARTADVENTURE.YES, cb = yes },
        { text = popup_data.no or STRINGS.UI.STARTADVENTURE.NO, cb = no },
    }

    -- en yes
    local bodytext = popup_data.body
    -- jp no
    -- local bodytext = "このポータルに入ると、マクスウェルを捜す長く険しい旅が始まる。ランダムに現れる5つの過酷な世界を冒険し、生きて脱出しなければならない。\n\n途中で息絶えると、またこのポータルの前に戻ってくる。ただし、マクスウェルを捜す旅は最初からやり直しになる。"
    -- zh no
    -- local bodytext = "你即将步入寻找麦斯威尔的漫长旅程，这条道路充满了艰险。你需要活着闯过5个随机生成的世界，每个世界都有一个独特的挑战等着你。\n\n如果你死了，你会安全重新回到这扇门，但这段旅程的所有进度均会丢失。"
    -- french yes
    -- local bodytext = "Si vous mourez en mode Aventure, vous serez ramené à ce portail, d'où vous pourrez redémarrer votre aventure.\n\nVous allez vous engager dans une expédition longue et difficile pour localiser Maxwell. Vous devrez survivre à cinq mondes générés de façon aléatoire, chacun offrant un défi unique."
    -- german yes
    -- local bodytext = "Wenn du im Abenteuer-Modus stirbst, wirst du zu diesem Portal zurückkehren, wo du das Abenteuer neu beginnen kannst.\n\nDu stehst vor einer langen, beschwerlichen Expedition, um Maxwell zu finden. Du musst fünf zufällig generierte Welten überleben, die alle eine ganz besondere Herausforderung präsentieren."
    -- kr yes
    -- local bodytext = "모험 모드에서 죽으면 이 포털로 돌아와서 모험을 다시 시작할 수 있습니다.\n\n이제 맥스웰을 찾기 위한 길고 고된 모험을 시작할 것입니다. 무작위로 생성된 5개의 세계에서 차례대로 고유한 난관을 만나며 생존해야 합니다."
    -- polish yes
    -- local bodytext = "Gdyby zdarzyło ci zginąć, twoja dusza bezpiecznie powróci do tego portalu, gdzie zawsze możesz rozpocząć przygodę od nowa.\n\nOto ruszasz w długą i niebezpieczną podróż, aby odnaleźć Maxwella. Twoim zadaniem będzie przetrwanie w pięciu losowo generowanych światach, które postawią cię przed wyjątkowymi wyzwaniami."
    -- portuguese yes
    -- local bodytext = "Se você morrer no modo de aventura, voltará para este portal, onde pode reiniciar a aventura.\n\nVocê está prestes a embarcar em uma longa e árdua expedição para encontrar Maxwell. Você precisará sobreviver a cinco mundos gerados aleatoriamente, cada um apresentando um desafio único a você."
    -- spanish
    -- local bodytext = "Si mueres durante el modo aventura regresarás a salvo a este portal, donde puedes volver a iniciarla.\n\nEstás a punto de embarcarte en una larga y ardua expedición para encontrar a Maxwell. Tendrás que sobrevivir en cinco mundos generados al azar, que cada uno te ofrecerá un desafío único."
    -- ru yes
    -- local bodytext = "Если вы умрете в режиме приключений, вы вернетесь к этому порталу, где сможете начать свой путь заново.\n\nВы отправляетесь в непростое и продолжительное странствие в поисках Максвелла. Вы должны любой ценой выжить в пяти мирах, созданных случайным образом, и каждый из них станет для вас настоящим испытанием."
    -- local bodytext = "你即将步入寻找麦斯威尔的漫长旅程，这条道路充满了艰险。你需要活着闯过5个随机生成的世界，每个世界都有一个独特的挑战等着你。\n\n如果你死了，你会安全重新回到这扇门，但这段旅程的所有进度均会丢失。"
    local Screen = PopupDialogScreen(popup_data.title or STRINGS.UI.STARTADVENTURE.TITLE, bodytext, buttons, nil, "big", "dark_wide")

    Screen.dialog.body:SetFont(DEFAULTFONT)
    Screen.dialog.body:SetSize(24)
    Screen.dialog.body:EnableWordWrap(true)
    Screen.dialog.body:EnableWhitespaceWrap(true)
    Screen.dialog.body:SetString(bodytext)

    TheFrontEnd:PushScreen(Screen)
end)

AddClientModRPCHandler("AdventureMode", "TeleportatoDenied", function()
    if ThePlayer ~= nil and ThePlayer.components.talker ~= nil then
        ThePlayer.components.talker:Say(STRINGS.UI.TELEPORTFAIL or "Everyone must stand near the Teleportato.")
    end
end)
