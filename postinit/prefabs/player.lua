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

local function GetAdventureState()
    return ShardGameIndex.adventure:GetState()
end

local function GetAdventureLevel()
    return ShardGameIndex.adventure:GetLevel()
end

local function GetAdventureTitleData()
    local state = GetAdventureState()
    local preset = GetAdventureLevel()

    local level = preset ~= nil and ADVENTURE_TITLE_BY_PRESET[preset] or nil
    level = level or tostring(preset or "Adventure")

    local chapter = state ~= nil and state.chapter or 1
    local total = state ~= nil and (state.total_chapters or (state.level_sequence ~= nil and #state.level_sequence)) or 1

    return level, string.format("Chapter %d of %d", chapter, total)
end

local function GetAdventureTitleKey()
    local state = GetAdventureState()
    local preset = GetAdventureLevel()

    return table.concat({
        tostring(state ~= nil and state.sequence_id or "default"),
        tostring(state ~= nil and state.started_at or ""),
        tostring(state ~= nil and state.current_session_id or ""),
        tostring(state ~= nil and state.chapter or 1),
        tostring(preset or "Adventure"),
    }, ":")
end

local function ShowAdventureTitle(inst, retries)
    if not TheWorld:IsAdventureActive() then
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

    local title_key = GetAdventureTitleKey()
    if sent_adventure_title_by_userid[inst.userid] == title_key then
        return
    end

    local level, chapter = GetAdventureTitleData()
    SendModRPCToClient(GetClientModRPC("AdventureMode", "ShowTitle"), inst.userid, level, chapter, play_maxwell_intro)
    sent_adventure_title_by_userid[inst.userid] = title_key
end

local function OnLocalPlayerActivated(inst)
    if TheFrontEnd ~= nil then
        TheFrontEnd:OnLocalPlayerActivated(inst)
    end
end

local function OnLocalPlayerDeactivated(inst)
    if TheFrontEnd ~= nil then
        TheFrontEnd:OnLocalPlayerDeactivated(inst)
    end
end

local function RememberStartingInventory(inst)
    ShardGameIndex.adventure:RememberStartingInventory(inst)
end

local function OnAdventurePlayerActivated(inst)
    ShardGameIndex.adventure:OnPlayerActivated(inst)
end

local function OnAdventurePlayerDeactivated(inst)
    if inst ~= nil and inst.userid ~= nil and inst.userid ~= "" then
        local maxwell_intro = inst.components.maxwellintrospawner
        if maxwell_intro ~= nil and maxwell_intro:ShouldPlayCurrentChapter() then
            sent_adventure_title_by_userid[inst.userid] = nil
        end
    end
    ShardGameIndex.adventure:OnPlayerDeactivated(inst)
end

local function OnAdventurePlayerDeath(inst)
    if TheWorld ~= nil and TheWorld.StartAdventureDeathCheck ~= nil then
        TheWorld:StartAdventureDeathCheck()
    end
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
