GLOBAL.setfenv(1, GLOBAL)

local TITLE_FADE_TIME = 1
local TITLE_BLANK_TIME = .75
local TITLE_ANIM_TIME = 4
local TITLE_ACTIVATE_LEAD_TIME = 1
local TITLE_FADE_TYPE = "black"
local ACTIVE_FADE_TITLE_WAIT_TIME = .75

local title = nil
local active_fade = nil
local fade_timeout_task = nil
local title_start_task = nil
local title_activate_task = nil
local wait_for_activate_fade = nil

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

local function RequestMaxwellIntroAfterTitle(data)
    if data ~= nil and data.play_maxwell_intro and ThePlayer ~= nil then
        if AdventureModeBeginMaxwellIntroCutscene ~= nil then
            AdventureModeBeginMaxwellIntroCutscene()
        end
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

local _Fade = FrontEnd.Fade
function FrontEnd:Fade(...)
    if not ConsumeActivateFade(self, _Fade, ...) then
        return _Fade(self, ...)
    end
end
