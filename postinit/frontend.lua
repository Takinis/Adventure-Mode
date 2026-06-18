GLOBAL.setfenv(1, GLOBAL)

local TITLE_FADE_TIME, TITLE_HOLD_TIME = 1, 3
local TITLE_FADE_TYPE = "black"
local ACTIVE_FADE_TITLE_WAIT_TIME = .75

local title = nil
local active_fade = nil
local fade_timeout_task = nil
local wait_for_activate_fade = nil

local function CancelFadeTimeout()
    if fade_timeout_task ~= nil then
        fade_timeout_task:Cancel()
        fade_timeout_task = nil
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

local function StartTitleFade(fade)
    local data = title
    if data == nil then
        return false
    end

    title = nil

    ClearFrontEnd(fade.fe)
    fade.fe:ShowTitle(data.level, data.chapter)
    fade.fn(fade.fe, FADE_IN, TITLE_FADE_TIME, function()
        if fade.cb ~= nil then
            fade.cb()
        end
        fade.fe:HideTitle()
    end, TITLE_HOLD_TIME, nil, TITLE_FADE_TYPE)

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

local function QueueAdventureTitle(level, chapter)
    if active_fade ~= nil then
        title = { level = level, chapter = chapter }
        CancelFadeTimeout()
        ResumeActivateFade()
    elseif wait_for_activate_fade ~= false then
        title = { level = level, chapter = chapter }
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
    end
end

function FrontEnd:QueueAdventureTitle(level, chapter)
    QueueAdventureTitle(level, chapter)
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
