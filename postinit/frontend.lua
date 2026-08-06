GLOBAL.setfenv(1, GLOBAL)

local TITLE_FADE_TIME = 1
local TITLE_BLANK_TIME = .75
local TITLE_ANIM_TIME = 4
local TITLE_FADE_TYPE = "black"
local ACTIVATION_PRESENTATION_WAIT_TIME = .75
local MAXWELL_INTRO_START_TIMEOUT = 50
local MAXWELL_INTRO_RELEASE_TIME = 1.5
local TITLE_SILENCE_MIX = "adventure_title_silence"
local MAXWELL_INTRO_INPUTS =
{
    CONTROL_PRIMARY,
    CONTROL_SECONDARY,
    CONTROL_ATTACK,
    CONTROL_INSPECT,
    CONTROL_ACTION,
    CONTROL_CONTROLLER_ACTION,
}

if TheNet ~= nil and TheNet:IsDedicated() then
    return
end

TheMixer:AddNewMix(TITLE_SILENCE_MIX, 0, 2147483646,
{
    ["set_ambience/ambience"] = 0,
    ["set_ambience/cloud"] = 0,
    ["set_music/soundtrack"] = 0,
    ["set_sfx/voice"] = 0,
    ["set_sfx/movement"] = 0,
    ["set_sfx/creature"] = 0,
    ["set_sfx/player"] = 0,
    ["set_sfx/HUD"] = 0,
    ["set_sfx/sfx"] = 0,
    ["set_sfx/everything_else_muted"] = 0,
})

local AdventureWaitingPopup = require("screens/adventurewaitingpopup")

local queued_presentation = nil
local active_presentation = nil
local activation_fade = nil
local activation_wait_task = nil
local wait_for_activation_fade = nil
local maxwell_intro = nil
local maxwell_intro_release_task = nil
local waiting_popup = nil
local title_silence_active = false
local title_silence_owner = nil
local _Fade = FrontEnd.Fade

local function StartTitleSilence(presentation)
    if not title_silence_active then
        title_silence_active = true
        TheMixer:PushMix(TITLE_SILENCE_MIX)
    end
    title_silence_owner = presentation
end

local function StopTitleSilence(presentation)
    if presentation ~= nil and title_silence_owner ~= presentation then
        return
    end

    if title_silence_active then
        title_silence_active = false
        TheMixer:DeleteMix(TITLE_SILENCE_MIX)
    end
    title_silence_owner = nil
end

local function CancelTask(task)
    if task ~= nil then
        task:Cancel()
    end
end

local function ScheduleTask(delay, fn)
    local host = TheWorld or ThePlayer
    if host ~= nil then
        return host:DoStaticTaskInTime(delay, fn)
    end
    fn()
end

local function ClearFrontEnd(fe)
    if global_loading_widget ~= nil and global_loading_widget.is_enabled then
        global_loading_widget:SetEnabled(false)
    end
    if fe == nil then
        return
    end

    for _, widget in pairs({
        fe.whiteoverlay,
        fe.vigoverlay,
        fe.topwhiteoverlay,
        fe.topvigoverlay,
        fe.swipeoverlay,
        fe.topswipeoverlay,
    }) do
        if widget ~= nil then
            widget:Hide()
        end
    end
end

local function RunActivationCallback(presentation)
    local fade = presentation ~= nil and presentation.fade or nil
    if fade ~= nil and fade.cb ~= nil then
        local cb = fade.cb
        fade.cb = nil
        cb()
    end
end

local function ClearPresentationTasks(presentation)
    if presentation == nil then
        return
    end
    CancelTask(presentation.show_title_task)
    CancelTask(presentation.intro_timeout_task)
    presentation.show_title_task = nil
    presentation.intro_timeout_task = nil
end

local function CloseWaitingPopup()
    if waiting_popup ~= nil then
        TheFrontEnd:PopScreen(waiting_popup)
        waiting_popup = nil
    end
end

local function ShowWaitingPopup()
    if waiting_popup == nil then
        waiting_popup = AdventureWaitingPopup()
        TheFrontEnd:PushScreen(waiting_popup)
    end
end

local function FinishPresentation(presentation)
    if presentation == nil or active_presentation ~= presentation then
        return
    end
    ClearPresentationTasks(presentation)
    RunActivationCallback(presentation)
    active_presentation = nil
end

local function RevealWorld(presentation)
    if presentation == nil or active_presentation ~= presentation then
        return
    end

    presentation.phase = "revealing"
    local fade = presentation.fade
    fade.fn(fade.fe, FADE_IN, TITLE_FADE_TIME, function()
        FinishPresentation(presentation)
    end, nil, nil, TITLE_FADE_TYPE)
end

local function AbortPresentation(presentation_id)
    local presentation = active_presentation
    if presentation == nil or presentation.id ~= presentation_id or
        (presentation.phase ~= "waiting_for_title" and presentation.phase ~= "title" and
            presentation.phase ~= "waiting_for_intro") then
        return
    end
    ClearPresentationTasks(presentation)
    CloseWaitingPopup()
    TheFrontEnd:HideTitle()
    StopTitleSilence(presentation)
    RevealWorld(presentation)
end

local function RestartIntroTimeout(presentation)
    CancelTask(presentation.intro_timeout_task)
    presentation.intro_timeout_task = ScheduleTask(MAXWELL_INTRO_START_TIMEOUT, function()
        presentation.intro_timeout_task = nil
        AbortPresentation(presentation.id)
    end)
end

local function WaitForPlayers(presentation)
    if active_presentation ~= presentation then
        return
    end

    presentation.phase = "waiting_for_title"
    RunActivationCallback(presentation)
    CloseWaitingPopup()
    ShowWaitingPopup()
    _Fade(TheFrontEnd, FADE_IN, 0, nil, nil, nil, TITLE_FADE_TYPE)
    SendModRPCToServer(GetModRPC("AdventureMode", "AdventurePresentationReady"), presentation.id)
    RestartIntroTimeout(presentation)
end

local function StartTitle(presentation)
    if presentation == nil or active_presentation ~= presentation then
        return
    end

    local fade = presentation.fade
    presentation.phase = "title"
    StartTitleSilence(presentation)
    if presentation.play_maxwell_intro then
        RestartIntroTimeout(presentation)
    end
    CloseWaitingPopup()
    ClearFrontEnd(fade.fe)
    fade.fe:HideTitle()

    presentation.show_title_task = ScheduleTask(TITLE_BLANK_TIME, function()
        presentation.show_title_task = nil
        if active_presentation == presentation then
            fade.fe:ShowTitle(presentation.title, presentation.subtitle)
        end
    end)

    local function OnTitleFinished()
        StopTitleSilence(presentation)
        if active_presentation ~= presentation then
            return
        end
        fade.fe:HideTitle()
        if presentation.play_maxwell_intro then
            presentation.phase = "waiting_for_intro"
            _Fade(TheFrontEnd, FADE_OUT, 0, nil, nil, nil, TITLE_FADE_TYPE)
            SendModRPCToServer(GetModRPC("AdventureMode", "AdventureTitleFinished"), presentation.id)
        end
    end

    local on_fade_in_complete = nil
    if not presentation.play_maxwell_intro then
        on_fade_in_complete = function()
            FinishPresentation(presentation)
        end
    end

    fade.fn(
        fade.fe,
        FADE_IN,
        TITLE_FADE_TIME,
        on_fade_in_complete,
        TITLE_BLANK_TIME + TITLE_ANIM_TIME,
        OnTitleFinished,
        TITLE_FADE_TYPE
    )
end

local function StartSinglePlayerPresentation(presentation)
    RunActivationCallback(presentation)
    SendModRPCToServer(GetModRPC("AdventureMode", "AdventurePresentationReady"), presentation.id)
    StartTitle(presentation)
end

local function StartPresentation(fade)
    local presentation = queued_presentation
    if presentation == nil then
        return false
    end

    queued_presentation = nil
    presentation.fade = fade
    active_presentation = presentation

    if presentation.play_maxwell_intro and presentation.wait_for_players then
        WaitForPlayers(presentation)
    elseif presentation.play_maxwell_intro then
        StartSinglePlayerPresentation(presentation)
    else
        StartTitle(presentation)
    end
    return true
end

local function ResumeActivationFade()
    activation_wait_task = nil
    local fade = activation_fade
    activation_fade = nil
    if fade == nil then
        return
    end

    if not StartPresentation(fade) then
        fade.fn(fade.fe, FADE_IN, fade.time, fade.cb, fade.delay, fade.delaycb, fade.fade_type)
    end
end

local function ConsumeActivationFade(fe, fade_fn, fade_dir, fade_time, cb, delay, delaycb, fade_type)
    if fe ~= TheFrontEnd or fade_dir ~= FADE_IN or not wait_for_activation_fade then
        return false
    end

    wait_for_activation_fade = false
    activation_fade =
    {
        fe = fe,
        fn = fade_fn,
        time = fade_time,
        cb = cb,
        delay = delay,
        delaycb = delaycb,
        fade_type = fade_type,
    }

    if StartPresentation(activation_fade) then
        activation_fade = nil
    else
        activation_wait_task = ScheduleTask(ACTIVATION_PRESENTATION_WAIT_TIME, ResumeActivationFade)
    end
    return true
end

local function StartStandalonePresentation()
    if queued_presentation == nil or active_presentation ~= nil then
        return
    end

    _Fade(TheFrontEnd, FADE_OUT, TITLE_FADE_TIME, function()
        StartPresentation({
            fe = TheFrontEnd,
            fn = _Fade,
            time = TITLE_FADE_TIME,
            fade_type = TITLE_FADE_TYPE,
        })
    end, nil, nil, TITLE_FADE_TYPE)
end

local function QueueAdventurePresentation(presentation_id, title, subtitle, play_maxwell_intro, wait_for_players)
    if type(presentation_id) ~= "string" or presentation_id == "" then
        return
    end
    if active_presentation ~= nil and active_presentation.id == presentation_id then
        return
    end
    if queued_presentation ~= nil and queued_presentation.id == presentation_id then
        return
    end

    queued_presentation =
    {
        id = presentation_id,
        title = title,
        subtitle = subtitle,
        play_maxwell_intro = play_maxwell_intro == true,
        wait_for_players = wait_for_players == true,
    }

    if activation_fade ~= nil then
        CancelTask(activation_wait_task)
        activation_wait_task = nil
        ResumeActivationFade()
    elseif wait_for_activation_fade == false then
        StartStandalonePresentation()
    end
end

local function ClearMaxwellIntroInputHandlers()
    if maxwell_intro ~= nil and maxwell_intro.inputhandlers ~= nil then
        for _, handler in ipairs(maxwell_intro.inputhandlers) do
            handler:Remove()
        end
        maxwell_intro.inputhandlers = nil
    end
end

local function SendSkipMaxwellIntro()
    if maxwell_intro ~= nil and maxwell_intro.guid ~= nil then
        SendModRPCToServer(
            GetModRPC("AdventureMode", "SkipMaxwellIntro"),
            maxwell_intro.presentation_id,
            maxwell_intro.guid
        )
    end
end

local function UpdateAdventurePresentationWait(presentation_id, ready, total)
    local presentation = active_presentation
    if presentation == nil or presentation.id ~= presentation_id or presentation.phase ~= "waiting_for_title" then
        return
    end

    ShowWaitingPopup()
    waiting_popup:SetProgress(ready, total)
end

local function StartAdventureTitle(presentation_id)
    local presentation = active_presentation
    if presentation == nil or presentation.id ~= presentation_id or presentation.phase ~= "waiting_for_title" then
        return
    end
    StartTitle(presentation)
end

local function StartMaxwellIntroCutscene(presentation_id, guid, x, y, z, can_skip)
    local presentation = active_presentation
    local player = ThePlayer
    if presentation == nil or presentation.id ~= presentation_id or presentation.phase ~= "waiting_for_intro" or
        player == nil or not player:IsValid() then
        return
    end

    CancelTask(presentation.intro_timeout_task)
    presentation.intro_timeout_task = nil
    presentation.phase = "intro"
    StopTitleSilence()
    CloseWaitingPopup()
    CancelTask(maxwell_intro_release_task)
    maxwell_intro_release_task = nil

    maxwell_intro =
    {
        presentation_id = presentation_id,
        guid = guid,
        inputhandlers = {},
    }

    if player.HUD ~= nil then
        player.HUD:Hide()
    end
    player:ForceFacePoint(x, y, z)

    if TheCamera ~= nil then
        local px, py, pz = player.Transform:GetWorldPosition()
        TheCamera:SetOffset((Vector3(x, y, z) - Vector3(px, py, pz)) * .5 + Vector3(0, 2, 0))
        TheCamera:SetDistance(15)
        TheCamera:Snap()
    end

    if can_skip and TheInput ~= nil then
        for _, control in ipairs(MAXWELL_INTRO_INPUTS) do
            table.insert(maxwell_intro.inputhandlers, TheInput:AddControlHandler(control, SendSkipMaxwellIntro))
        end
    end

    _Fade(TheFrontEnd, FADE_IN, TITLE_FADE_TIME, nil, nil, nil, TITLE_FADE_TYPE)
    ClearPresentationTasks(presentation)
    active_presentation = nil
end

local function StopMaxwellIntroCutscene(presentation_id, guid)
    if maxwell_intro == nil or maxwell_intro.presentation_id ~= presentation_id or maxwell_intro.guid ~= guid then
        return
    end

    local player = ThePlayer
    ClearMaxwellIntroInputHandlers()
    maxwell_intro = nil

    maxwell_intro_release_task = ScheduleTask(MAXWELL_INTRO_RELEASE_TIME, function()
        maxwell_intro_release_task = nil
        if ThePlayer ~= player or player == nil or not player:IsValid() then
            return
        end
        if player.HUD ~= nil then
            player.HUD:Show()
        end
        if TheCamera ~= nil then
            TheCamera:SetDefault()
        end
    end)
end

local function OnLocalPlayerActivated(inst)
    if inst ~= ThePlayer then
        return
    end

    wait_for_activation_fade =
        TheWorld ~= nil and not TheWorld.isdeactivated and
        not inst.isseamlessswaptarget and
        (inst.player_classified == nil or inst.player_classified.isfadein:value())

    if not wait_for_activation_fade then
        StartStandalonePresentation()
    end
end

local function OnLocalPlayerDeactivated(inst)
    if inst ~= ThePlayer then
        return
    end

    wait_for_activation_fade = nil
    queued_presentation = nil
    ClearPresentationTasks(active_presentation)
    active_presentation = nil
    activation_fade = nil
    CancelTask(activation_wait_task)
    activation_wait_task = nil
    ClearMaxwellIntroInputHandlers()
    maxwell_intro = nil
    CancelTask(maxwell_intro_release_task)
    maxwell_intro_release_task = nil
    StopTitleSilence()
    CloseWaitingPopup()
    TheFrontEnd:HideTitle()
    if inst.HUD ~= nil then
        inst.HUD:Show()
    end
    if TheCamera ~= nil then
        TheCamera:SetDefault()
    end
end

function FrontEnd:QueueAdventurePresentation(presentation_id, title, subtitle, play_maxwell_intro, wait_for_players)
    QueueAdventurePresentation(presentation_id, title, subtitle, play_maxwell_intro, wait_for_players)
end

function FrontEnd:AbortAdventurePresentation(presentation_id)
    AbortPresentation(presentation_id)
end

function FrontEnd:UpdateAdventurePresentationWait(presentation_id, ready, total)
    UpdateAdventurePresentationWait(presentation_id, ready, total)
end

function FrontEnd:StartAdventureTitle(presentation_id)
    StartAdventureTitle(presentation_id)
end

function FrontEnd:OnLocalPlayerActivated(inst)
    OnLocalPlayerActivated(inst)
end

function FrontEnd:OnLocalPlayerDeactivated(inst)
    OnLocalPlayerDeactivated(inst)
end

function FrontEnd:StartMaxwellIntroCutscene(presentation_id, guid, x, y, z, can_skip)
    StartMaxwellIntroCutscene(presentation_id, guid, x, y, z, can_skip)
end

function FrontEnd:StopMaxwellIntroCutscene(presentation_id, guid)
    StopMaxwellIntroCutscene(presentation_id, guid)
end

function FrontEnd:Fade(...)
    if not ConsumeActivationFade(self, _Fade, ...) then
        return _Fade(self, ...)
    end
end
