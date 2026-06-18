GLOBAL.setfenv(1, GLOBAL)

local TITLE_FADE_TIME = 1
local TITLE_BLANK_TIME = .75
local TITLE_ANIM_TIME = 4
local TITLE_ACTIVATE_LEAD_TIME = 1
local TITLE_FADE_TYPE = "black"
local ACTIVE_FADE_TITLE_WAIT_TIME = .75
local MAXWELL_INTRO_INPUTS =
{
    CONTROL_PRIMARY,
    CONTROL_SECONDARY,
    CONTROL_ATTACK,
    CONTROL_INSPECT,
    CONTROL_ACTION,
    CONTROL_CONTROLLER_ACTION,
}

local title = nil
local active_fade = nil
local fade_timeout_task = nil
local title_start_task = nil
local title_activate_task = nil
local wait_for_activate_fade = nil
local maxwell_intro_state = nil

local function CancelFadeTimeout()
    if fade_timeout_task ~= nil then
        fade_timeout_task:Cancel()
        fade_timeout_task = nil
    end
end

local function CancelTitleStartTask()
    if title_start_task ~= nil then
        title_start_task:Cancel()
        title_start_task = nil
    end
end

local function CancelTitleActivateTask()
    if title_activate_task ~= nil then
        title_activate_task:Cancel()
        title_activate_task = nil
    end
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

local function StopMaxwellIntroCutscene(guid)
    if maxwell_intro_state ~= nil and guid ~= nil and maxwell_intro_state.guid ~= guid then
        return
    end

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

local function RequestMaxwellIntroAfterTitle(data)
    if data ~= nil and data.play_maxwell_intro and ThePlayer ~= nil then
        TheFrontEnd:BeginMaxwellIntroCutscene()
        SendModRPCToServer(GetModRPC("AdventureMode", "RequestMaxwellIntroAfterTitle"))
    end
end

local function StartTitleFade(fade)
    local data = title
    if data == nil then
        return false
    end

    title = nil

    CancelTitleStartTask()
    CancelTitleActivateTask()
    ClearFrontEnd(fade.fe)

    local function ShowQueuedTitle()
        title_start_task = nil
        if fade.fe ~= nil then
            fade.fe:ShowTitle(data.level, data.chapter)
        end
    end

    if TheWorld ~= nil or ThePlayer ~= nil then
        title_start_task = (TheWorld or ThePlayer):DoStaticTaskInTime(TITLE_BLANK_TIME, ShowQueuedTitle)
    else
        ShowQueuedTitle()
    end

    local activated = false
    local function ActivateBeforeTitleEnds()
        if not activated then
            activated = true
            if fade.cb ~= nil then
                local cb = fade.cb
                fade.cb = nil
                cb()
            end
            RequestMaxwellIntroAfterTitle(data)
        end
    end

    local function RunActivateTask()
        title_activate_task = nil
        ActivateBeforeTitleEnds()
    end

    local activate_time = math.max(0, TITLE_BLANK_TIME + TITLE_ANIM_TIME - TITLE_ACTIVATE_LEAD_TIME)
    if TheWorld ~= nil or ThePlayer ~= nil then
        title_activate_task = (TheWorld or ThePlayer):DoStaticTaskInTime(activate_time, RunActivateTask)
    else
        ActivateBeforeTitleEnds()
    end

    fade.fn(fade.fe, FADE_IN, TITLE_FADE_TIME, function()
        CancelTitleStartTask()
        CancelTitleActivateTask()
        ActivateBeforeTitleEnds()
        fade.fe:HideTitle()
    end, TITLE_BLANK_TIME + TITLE_ANIM_TIME, nil, TITLE_FADE_TYPE)

    return true
end

local function ResumeActivateFade()
    fade_timeout_task = nil

    local fade = active_fade
    if fade == nil then
        return
    end

    active_fade = nil
    if not StartTitleFade(fade) then
        fade.fn(fade.fe, FADE_IN, fade.time, fade.cb, fade.delay, fade.delaycb, fade.fade_type)
    end
end

local function ConsumeActivateFade(fe, fade_fn, fade_dir, fade_time, cb, delay, delaycb, fade_type)
    if fe ~= TheFrontEnd or fade_dir ~= FADE_IN or not wait_for_activate_fade then
        return false
    end

    wait_for_activate_fade = false
    active_fade = {
        fe = fe,
        fn = fade_fn,
        time = fade_time,
        cb = cb,
        delay = delay,
        delaycb = delaycb,
        fade_type = fade_type,
    }

    if StartTitleFade(active_fade) then
        active_fade = nil
    elseif TheWorld ~= nil or ThePlayer ~= nil then
        fade_timeout_task = (TheWorld or ThePlayer):DoStaticTaskInTime(ACTIVE_FADE_TITLE_WAIT_TIME, ResumeActivateFade)
    else
        ResumeActivateFade()
    end

    return true
end

local function QueueAdventureTitle(level, chapter, play_maxwell_intro)
    if active_fade ~= nil then
        title = { level = level, chapter = chapter, play_maxwell_intro = play_maxwell_intro == true }
        CancelFadeTimeout()
        ResumeActivateFade()
    elseif wait_for_activate_fade ~= false then
        title = { level = level, chapter = chapter, play_maxwell_intro = play_maxwell_intro == true }
    end
end

local function OnLocalPlayerActivated(fe, inst)
    if inst == ThePlayer then
        wait_for_activate_fade =
            TheWorld ~= nil and not TheWorld.isdeactivated and
            not inst.isseamlessswaptarget and
            (inst.player_classified == nil or inst.player_classified.isfadein:value())

        if not wait_for_activate_fade then
            title = nil
        end
    end
end

local function OnLocalPlayerDeactivated(fe, inst)
    if inst == ThePlayer then
        wait_for_activate_fade = nil
        title = nil
        active_fade = nil
        CancelFadeTimeout()
        CancelTitleStartTask()
        CancelTitleActivateTask()
    end
end

function FrontEnd:QueueAdventureTitle(level, chapter, play_maxwell_intro)
    QueueAdventureTitle(level, chapter, play_maxwell_intro)
end

function FrontEnd:OnLocalPlayerActivated(inst)
    OnLocalPlayerActivated(self, inst)
end

function FrontEnd:OnLocalPlayerDeactivated(inst)
    OnLocalPlayerDeactivated(self, inst)
end

function FrontEnd:BeginMaxwellIntroCutscene()
    StartMaxwellIntroCutscene(nil)
end

function FrontEnd:StartMaxwellIntroCutscene(guid, x, y, z)
    StartMaxwellIntroCutscene(guid, x, y, z)
end

function FrontEnd:StopMaxwellIntroCutscene(guid)
    StopMaxwellIntroCutscene(guid)
end

local _Fade = FrontEnd.Fade
function FrontEnd:Fade(...)
    if not ConsumeActivateFade(self, _Fade, ...) then
        return _Fade(self, ...)
    end
end
