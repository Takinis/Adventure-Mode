local AddPlayerPostInit = AddPlayerPostInit
GLOBAL.setfenv(1, GLOBAL)

local TITLE_RETRY_TIME = FRAMES
local TITLE_SEND_RETRY_LIMIT = 30

local sent_adventure_title_by_userid = {}

local ADVENTURE_TITLE_BY_PRESET =
{
    RAINY = "A Cold Reception",
    WINTER = "The King of Winter",
    HUB = "The Game is Afoot",
    ISLANDHOP = "Archipelago",
    TWOLANDS = "Two Worlds",
    DARKNESS = "Darkness",
    ENDING = "Checkmate",
}

local function GetAdventureTitleData()
    local state = ShardGameIndex ~= nil and ShardGameIndex:GetAdventureState() or nil
    local preset = state ~= nil and state.current_preset or nil
    if type(preset) == "table" then
        preset = preset.id or preset.worldgen_preset or preset.preset
    end

    local level = preset ~= nil and ADVENTURE_TITLE_BY_PRESET[preset] or nil
    level = level or tostring(preset or "Adventure")

    local chapter = state ~= nil and state.chapter or 1
    local total = state ~= nil and state.level_sequence ~= nil and #state.level_sequence or 1

    return level, string.format("Chapter %d of %d", chapter, total)
end

local function IsAdventureActive()
    return ShardGameIndex ~= nil and ShardGameIndex:IsAdventureActive()
end

local function ShowAdventureTitle(inst, retries)
    if not IsAdventureActive() then
        return
    end

    if inst == nil or inst.userid == nil or inst.userid == "" then
        retries = (retries or 0) + 1
        if inst ~= nil and retries <= TITLE_SEND_RETRY_LIMIT then
            inst:DoTaskInTime(TITLE_RETRY_TIME, ShowAdventureTitle, retries)
        end
        return
    end

    if sent_adventure_title_by_userid[inst.userid] then
        return
    end

    local level, chapter = GetAdventureTitleData()
    SendModRPCToClient(GetClientModRPC("AdventureMode", "ShowTitle"), inst.userid, level, chapter)
    sent_adventure_title_by_userid[inst.userid] = true
end

AddPlayerPostInit(function(inst)
    if not TheWorld.ismastersim then
        return
    end

    inst:ListenForEvent("playeractivated", AD_RPC_FN.OnLocalPlayerActivated)
    inst:ListenForEvent("playerdeactivated", AD_RPC_FN.OnLocalPlayerDeactivated)

    inst:ListenForEvent("playeractivated", ShowAdventureTitle)
    inst:DoTaskInTime(0, ShowAdventureTitle)
end)
