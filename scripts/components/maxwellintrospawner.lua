local MAXWELL_SPEECH_BY_CHAPTER =
{
    "ADVENTURE_1",
    "ADVENTURE_2",
    "ADVENTURE_3",
    "ADVENTURE_4",
    "ADVENTURE_5",
    "ADVENTURE_6",
}

local MaxwellIntroSpawner = Class(function(self, inst)
    self.inst = inst
end)

local function GetCurrentAdventureState()
    return ShardGameIndex:GetAdventureState()
end

local function GetPlayerUserid(inst)
    local userid = inst ~= nil and inst.userid or nil
    return type(userid) == "string" and userid ~= "" and userid or nil
end

local function GetCurrentAdventureChapter()
    local state = GetCurrentAdventureState()
    local chapter = state ~= nil and state.chapter or nil
    return type(chapter) == "number" and chapter or nil
end

local function GetCurrentAdventurePreset()
    return ShardGameIndex:GetAdventurePreset()
end

local function GetCurrentAdventureSpeechName()
    local preset = GetCurrentAdventurePreset()
    if preset == "ENDING" then
        return nil
    end

    local chapter = GetCurrentAdventureChapter()
    if chapter == nil then
        return nil
    end

    return preset == "TWOLANDS" and "ADVENTURE_TWOLANDS" or MAXWELL_SPEECH_BY_CHAPTER[chapter]
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
    local userid = GetPlayerUserid(self.inst)
    if chapter == nil or userid == nil then
        return false
    end

    if ShardGameIndex:IsCurrentAdventureMaxwellIntroPlayed(userid) then
        return true
    end

    return false
end

function MaxwellIntroSpawner:ShouldPlayCurrentChapter()
    return GetPlayerUserid(self.inst) ~= nil and
        GetCurrentAdventureSpeechName() ~= nil and
        not self:IsCurrentChapterPlayed()
end

function MaxwellIntroSpawner:MarkCurrentChapterPlayed()
    local userid = GetPlayerUserid(self.inst)
    if userid == nil then
        return false
    end

    return ShardGameIndex:MarkCurrentAdventureMaxwellIntroPlayed(userid)
end

function MaxwellIntroSpawner:StartCurrentChapter()
    if self:IsCurrentChapterPlayed() then
        return false
    end

    local speech_name = GetCurrentAdventureSpeechName()
    if speech_name == nil then
        return false
    end

    if SpawnMaxwellIntroForPlayer(self.inst, speech_name) then
        self:MarkCurrentChapterPlayed()
        return true
    end

    return false
end

return MaxwellIntroSpawner
