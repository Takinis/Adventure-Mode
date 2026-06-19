local AddPlayerPostInit = AddPlayerPostInit
GLOBAL.setfenv(1, GLOBAL)

local TITLE_RETRY_TIME = FRAMES
local TITLE_SEND_RETRY_LIMIT = 30

local sent_adventure_title_by_userid = {}
local maxwell_intro_played = false
local maxwell_intro_player = nil
local maxwell_intro_release_task = nil

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

local MAXWELL_SPEECH_BY_CHAPTER =
{
    "ADVENTURE_1",
    "ADVENTURE_2",
    "ADVENTURE_3",
    "ADVENTURE_4",
    "ADVENTURE_5",
    "ADVENTURE_6",
}

local TWO_LANDS_DAY_SEGS = {
    longdusk = { day = 0.7, dusk = 1.6, night = 0.7 },
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

local function GetCurrentAdventurePreset()
    local state = ShardGameIndex ~= nil and ShardGameIndex:GetAdventureState() or nil
    local preset = state ~= nil and state.current_preset or nil

    if type(preset) == "table" then
        preset = preset.id or preset.worldgen_preset or preset.preset
    end

    return preset
end

local function GetCurrentAdventureSpeechName()
    local state = ShardGameIndex ~= nil and ShardGameIndex:GetAdventureState() or nil
    local chapter = state ~= nil and state.chapter or nil
    if type(chapter) ~= "number" then
        return nil
    end

    return GetCurrentAdventurePreset() == "TWOLANDS" and "ADVENTURE_TWOLANDS" or MAXWELL_SPEECH_BY_CHAPTER[chapter]
end

local function AreaHasTag(area, tag)
    if area == nil or area.tags == nil then
        return false
    end

    for _, area_tag in ipairs(area.tags) do
        if area_tag == tag then
            return true
        end
    end

    return false
end

local function ApplyTwoLandsPartsIslandTrigger(inst)
    -- huh?
    TheWorld:PushEvent("enter_parts_island", { player = inst, area = "parts_island" })

    if TheWorld.state.enter_parts_island then
        return
    end

    TheWorld.state.enter_parts_island = true
    TheWorld:PushEvent("ms_setprecipitationmode", "dynamic")
    TheWorld:PushEvent("ms_setmoisturescale", 2)
    TheWorld:PushEvent("ms_forceprecipitation", true)
    TheWorld:PushEvent("ms_setseasonsegmodifier", { day = 0.7, dusk = 1.6, night = 0.7 })
end

local function OnTwoLandsAreaChanged(inst, area)
    if AreaHasTag(area, "parts_island") then
        ApplyTwoLandsPartsIslandTrigger(inst)
    end
end

local function SpawnMaxwellIntroForPlayer(inst, speech_name)
    if TheWorld == nil or not TheWorld.ismastersim or inst == nil or inst.userid == nil or inst.userid == "" then
        return false
    end

    local maxwell = SpawnPrefab("maxwellintro")
    if maxwell == nil or maxwell.components.maxwelltalker == nil then
        if maxwell ~= nil then
            maxwell:Remove()
        end
        return false
    end

    maxwell.components.maxwelltalker:SetSpeech(speech_name)
    if maxwell.components.maxwelltalker:BeginSpeech(inst) then
        return true
    end

    if maxwell:IsValid() then
        maxwell:Remove()
    end
    return false
end

local function CancelMaxwellIntroReleaseTask()
    if maxwell_intro_release_task ~= nil then
        maxwell_intro_release_task:Cancel()
        maxwell_intro_release_task = nil
    end
end

local function ReleaseMaxwellIntroReservation(inst)
    if inst == nil or inst == maxwell_intro_player then
        if maxwell_intro_player ~= nil then
            maxwell_intro_player._adventure_maxwell_intro_speech = nil
        end
        maxwell_intro_player = nil
        CancelMaxwellIntroReleaseTask()
    end

    if inst ~= nil then
        inst._adventure_maxwell_intro_speech = nil
    end
end

local function TryReserveMaxwellIntroPlayer(inst)
    if maxwell_intro_played or maxwell_intro_player ~= nil then
        return false
    end

    if inst == nil or inst.userid == nil or inst.userid == "" then
        return false
    end

    local speech_name = GetCurrentAdventureSpeechName()
    if speech_name == nil then
        return false
    end

    maxwell_intro_player = inst
    inst._adventure_maxwell_intro_speech = speech_name
    CancelMaxwellIntroReleaseTask()
    maxwell_intro_release_task = inst:DoTaskInTime(20, ReleaseMaxwellIntroReservation, inst)
    return true
end

local function StartReservedMaxwellIntro(inst)
    if maxwell_intro_played or inst == nil or inst ~= maxwell_intro_player then
        return false
    end

    local speech_name = inst._adventure_maxwell_intro_speech or GetCurrentAdventureSpeechName()
    if speech_name == nil then
        return false
    end

    maxwell_intro_played = SpawnMaxwellIntroForPlayer(inst, speech_name) or maxwell_intro_played
    if maxwell_intro_played then
        ReleaseMaxwellIntroReservation(inst)
    end

    return maxwell_intro_played
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

    local play_maxwell_intro = TryReserveMaxwellIntroPlayer(inst)
    local level, chapter = GetAdventureTitleData()
    SendModRPCToClient(GetClientModRPC("AdventureMode", "ShowTitle"), inst.userid, level, chapter, play_maxwell_intro)
    sent_adventure_title_by_userid[inst.userid] = true
end

local function OnLocalPlayerActivated(inst)
    TheFrontEnd:OnLocalPlayerActivated(inst)
end

local function OnLocalPlayerDeactivated(inst)
    TheFrontEnd:OnLocalPlayerDeactivated(inst)
end

local function RememberStartingInventory(inst)
    ShardGameIndex:RememberStartingInventory(inst)
end

local function OnAdventurePlayerActivated(inst)
    ShardGameIndex:OnAdventurePlayerActivated(inst)
end

local function OnAdventurePlayerDeactivated(inst)
    ReleaseMaxwellIntroReservation(inst)
    ShardGameIndex:OnAdventurePlayerDeactivated(inst)
end

local function OnAdventurePlayerDeath(inst)
    ShardGameIndex:OnAdventurePlayerDeath(inst)
end

AddPlayerPostInit(function(inst)
    RememberStartingInventory(inst)

    if TheWorld ~= nil and TheWorld.ismastersim then
        inst.StartAdventureMaxwellIntro = StartReservedMaxwellIntro

        inst:ListenForEvent("death", OnAdventurePlayerDeath)
        inst:ListenForEvent("ms_becameghost", OnAdventurePlayerDeath)
        inst:ListenForEvent("playeractivated", OnAdventurePlayerActivated)
        inst:ListenForEvent("playerdeactivated", OnAdventurePlayerDeactivated)
        inst:ListenForEvent("playeractivated", ShowAdventureTitle)
        inst:DoTaskInTime(0, ShowAdventureTitle)
        inst:DoTaskInTime(0, OnAdventurePlayerActivated)

        if GetCurrentAdventurePreset() == "TWOLANDS" then
            inst:ListenForEvent("changearea", OnTwoLandsAreaChanged)
            inst:DoTaskInTime(0, function(inst)
                local areaaware = inst.components.areaaware
                if areaaware ~= nil then
                    areaaware:UpdatePosition(inst.Transform:GetWorldPosition())
                    OnTwoLandsAreaChanged(inst, areaaware:GetCurrentArea())
                end
            end)
        end
    end

    inst:ListenForEvent("playeractivated", OnLocalPlayerActivated)
    inst:ListenForEvent("playerdeactivated", OnLocalPlayerDeactivated)
end)
