local AddPlayerPostInit = AddPlayerPostInit
GLOBAL.setfenv(1, GLOBAL)

local TITLE_RETRY_TIME = FRAMES
local TITLE_SEND_RETRY_LIMIT = 30

local sent_adventure_title_by_userid = {}

local function GetAdventureRun()
    return ShardGameIndex.adventure:GetState()
end

local function GetAdventureTitleData(run)
    local preset = run ~= nil and run.current_preset or nil
    local chapter = run ~= nil and run.chapter or nil
    local total = run ~= nil and type(run.level_sequence) == "table" and #run.level_sequence or nil
    return preset, chapter, total
end

local function GetAdventurePresentationId(run, preset)

    return table.concat({
        tostring(run ~= nil and run.sequence_id or "default"),
        tostring(run ~= nil and run.started_at or ""),
        tostring(run ~= nil and run.current_session_id or ""),
        tostring(run ~= nil and run.chapter or ""),
        tostring(preset),
    }, ":")
end

local function ShowAdventureTitle(inst, retries)
    if not TheWorld.is_adventure then
        return
    end

    if inst == nil or inst.userid == nil or inst.userid == "" then
        retries = (retries or 0) + 1
        if inst ~= nil and retries <= TITLE_SEND_RETRY_LIMIT then
            inst:DoStaticTaskInTime(TITLE_RETRY_TIME, ShowAdventureTitle, retries)
        end
        return
    end

    local run = GetAdventureRun()
    local preset, chapter, total = GetAdventureTitleData(run)
    if preset == nil or chapter == nil or total == nil then
        retries = (retries or 0) + 1
        if retries <= TITLE_SEND_RETRY_LIMIT then
            inst:DoStaticTaskInTime(TITLE_RETRY_TIME, ShowAdventureTitle, retries)
        end
        return
    end

    local presentation_id = GetAdventurePresentationId(run, preset)
    if sent_adventure_title_by_userid[inst.userid] == presentation_id then
        return
    end

    local maxwell_intro = TheWorld.components.maxwellintrospawner
    local play_maxwell_intro = maxwell_intro ~= nil and
        maxwell_intro:PreparePlayer(inst, presentation_id) or false
    local wait_for_players = play_maxwell_intro and maxwell_intro:ShouldWaitForPlayers() or false

    SendModRPCToClient(
        GetClientModRPC("AdventureMode", "StartAdventurePresentation"),
        inst.userid,
        presentation_id,
        preset,
        chapter,
        total,
        play_maxwell_intro,
        wait_for_players
    )
    sent_adventure_title_by_userid[inst.userid] = presentation_id
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
        sent_adventure_title_by_userid[inst.userid] = nil
    end
    ShardGameIndex.adventure:OnPlayerDeactivated(inst)
end

AddPlayerPostInit(function(inst)
    RememberStartingInventory(inst)

    if TheWorld ~= nil and TheWorld.ismastersim then
        inst:ListenForEvent("playeractivated", OnAdventurePlayerActivated)
        inst:ListenForEvent("playerdeactivated", OnAdventurePlayerDeactivated)
        inst:ListenForEvent("playeractivated", ShowAdventureTitle)
        inst:DoStaticTaskInTime(0, ShowAdventureTitle)
        inst:DoTaskInTime(0, OnAdventurePlayerActivated)
    end

    if TheNet == nil or not TheNet:IsDedicated() then
        inst:ListenForEvent("playeractivated", OnLocalPlayerActivated)
        inst:ListenForEvent("playerdeactivated", OnLocalPlayerDeactivated)
    end
end)
