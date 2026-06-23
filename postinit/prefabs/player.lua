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
    local preset = ShardGameIndex ~= nil and ShardGameIndex.GetAdventurePreset ~= nil and
        ShardGameIndex:GetAdventurePreset() or nil

    local level = preset ~= nil and ADVENTURE_TITLE_BY_PRESET[preset] or nil
    level = level or tostring(preset or "Adventure")

    local chapter = state ~= nil and state.chapter or 1
    local total = state ~= nil and (state.total_chapters or (state.level_sequence ~= nil and #state.level_sequence)) or 1

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

    local maxwell_intro = inst.components.maxwellintrospawner
    local play_maxwell_intro = maxwell_intro ~= nil and maxwell_intro:ShouldPlayCurrentChapter() or false

    if sent_adventure_title_by_userid[inst.userid] then
        return
    end

    local level, chapter = GetAdventureTitleData()
    SendModRPCToClient(GetClientModRPC("AdventureMode", "ShowTitle"), inst.userid, level, chapter, play_maxwell_intro)
    sent_adventure_title_by_userid[inst.userid] = true
end

local function OnLocalPlayerActivated(inst)
    if TheFrontEnd ~= nil and TheFrontEnd.OnLocalPlayerActivated ~= nil then
        TheFrontEnd:OnLocalPlayerActivated(inst)
    end
end

local function OnLocalPlayerDeactivated(inst)
    if TheFrontEnd ~= nil and TheFrontEnd.OnLocalPlayerDeactivated ~= nil then
        TheFrontEnd:OnLocalPlayerDeactivated(inst)
    end
end

local function RememberStartingInventory(inst)
    ShardGameIndex:RememberStartingInventory(inst)
end

local function OnAdventurePlayerActivated(inst)
    ShardGameIndex:OnAdventurePlayerActivated(inst)
end

local function OnAdventurePlayerDeactivated(inst)
    if inst ~= nil and inst.userid ~= nil and inst.userid ~= "" then
        local maxwell_intro = inst.components.maxwellintrospawner
        if maxwell_intro ~= nil and maxwell_intro:ShouldPlayCurrentChapter() then
            sent_adventure_title_by_userid[inst.userid] = nil
        end
    end
    ShardGameIndex:OnAdventurePlayerDeactivated(inst)
end

local function OnAdventurePlayerDeath(inst)
    ShardGameIndex:OnAdventurePlayerDeath(inst)
end

AddPlayerPostInit(function(inst)
    RememberStartingInventory(inst)

    if TheWorld ~= nil and TheWorld.ismastersim then
        if inst.components.maxwellintrospawner == nil then
            inst:AddComponent("maxwellintrospawner")
        end

        inst:ListenForEvent("death", OnAdventurePlayerDeath)
        inst:ListenForEvent("ms_becameghost", OnAdventurePlayerDeath)
        inst:ListenForEvent("playeractivated", OnAdventurePlayerActivated)
        inst:ListenForEvent("playerdeactivated", OnAdventurePlayerDeactivated)
        inst:ListenForEvent("playeractivated", ShowAdventureTitle)
        inst:DoTaskInTime(0, ShowAdventureTitle)
        inst:DoTaskInTime(0, OnAdventurePlayerActivated)
    end

    if TheNet == nil or not TheNet:IsDedicated() then
        inst:ListenForEvent("playeractivated", OnLocalPlayerActivated)
        inst:ListenForEvent("playerdeactivated", OnLocalPlayerDeactivated)
    end
end)
