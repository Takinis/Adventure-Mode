local RELEASE_DELAY = 20

local MAXWELL_SPEECH_BY_CHAPTER =
{
    "ADVENTURE_1",
    "ADVENTURE_2",
    "ADVENTURE_3",
    "ADVENTURE_4",
    "ADVENTURE_5",
    "ADVENTURE_6",
}

local played_chapter = nil
local reserved_player = nil
local release_task = nil

local MaxwellIntroSpawner = Class(function(self, inst)
    self.inst = inst
    self.speech = nil
end)

local function GetCurrentAdventureState()
    return ShardGameIndex ~= nil and ShardGameIndex:GetAdventureState() or nil
end

local function GetCurrentAdventureChapter()
    local state = GetCurrentAdventureState()
    local chapter = state ~= nil and state.chapter or nil
    return type(chapter) == "number" and chapter or nil
end

local function GetCurrentAdventurePreset()
    local state = GetCurrentAdventureState()
    local preset = state ~= nil and state.current_preset or nil

    if type(preset) == "table" then
        preset = preset.id or preset.worldgen_preset or preset.preset
    end

    return preset
end

local function GetCurrentAdventureSpeechName()
    local chapter = GetCurrentAdventureChapter()
    if chapter == nil then
        return nil
    end

    return GetCurrentAdventurePreset() == "TWOLANDS" and "ADVENTURE_TWOLANDS" or MAXWELL_SPEECH_BY_CHAPTER[chapter]
end

local function CancelReleaseTask()
    if release_task ~= nil then
        release_task:Cancel()
        release_task = nil
    end
end

local function ClearReservedSpeech(inst)
    if inst ~= nil and inst.components ~= nil and inst.components.maxwellintrospawner ~= nil then
        inst.components.maxwellintrospawner.speech = nil
    end
end

local function ReleaseReservedPlayer(inst)
    if inst == nil or inst == reserved_player then
        ClearReservedSpeech(reserved_player)
        reserved_player = nil
        CancelReleaseTask()
    end

    ClearReservedSpeech(inst)
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

function MaxwellIntroSpawner:IsCurrentChapterPlayed()
    local chapter = GetCurrentAdventureChapter()
    if chapter == nil then
        return false
    end

    if played_chapter == chapter then
        return true
    end

    if ShardGameIndex ~= nil and
        ShardGameIndex.IsCurrentAdventureMaxwellIntroPlayed ~= nil and
        ShardGameIndex:IsCurrentAdventureMaxwellIntroPlayed() then
        played_chapter = chapter
        return true
    end

    return false
end

function MaxwellIntroSpawner:MarkCurrentChapterPlayed()
    played_chapter = GetCurrentAdventureChapter()
    if ShardGameIndex ~= nil and ShardGameIndex.MarkCurrentAdventureMaxwellIntroPlayed ~= nil then
        ShardGameIndex:MarkCurrentAdventureMaxwellIntroPlayed()
    end
end

function MaxwellIntroSpawner:TryReserve()
    if self:IsCurrentChapterPlayed() or reserved_player ~= nil then
        return false
    end

    local inst = self.inst
    if inst == nil or inst.userid == nil or inst.userid == "" then
        return false
    end

    local speech_name = GetCurrentAdventureSpeechName()
    if speech_name == nil then
        return false
    end

    reserved_player = inst
    self.speech = speech_name
    CancelReleaseTask()
    release_task = inst:DoTaskInTime(RELEASE_DELAY, function()
        self:ReleaseReservation()
    end)
    return true
end

function MaxwellIntroSpawner:StartReserved()
    if self:IsCurrentChapterPlayed() then
        self:ReleaseReservation()
        return false
    end

    if self.inst == nil or self.inst ~= reserved_player then
        return false
    end

    local speech_name = self.speech or GetCurrentAdventureSpeechName()
    if speech_name == nil then
        self:ReleaseReservation()
        return false
    end

    if SpawnMaxwellIntroForPlayer(self.inst, speech_name) then
        self:MarkCurrentChapterPlayed()
        self:ReleaseReservation()
        return true
    end

    return false
end

function MaxwellIntroSpawner:ReleaseReservation()
    ReleaseReservedPlayer(self.inst)
end

function MaxwellIntroSpawner:OnRemoveFromEntity()
    self:ReleaseReservation()
end

return MaxwellIntroSpawner
