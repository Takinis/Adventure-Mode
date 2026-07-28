local MAX_SYNCED_CHAPTER = 63

local function ClampChapter(value)
    value = type(value) == "number" and math.floor(value) or 0
    return math.clamp(value, 0, MAX_SYNCED_CHAPTER)
end

return Class(function(self, inst)
    self.inst = inst

    local _world = TheWorld
    local _ismastersim = _world.ismastersim

    local _active = net_bool(inst.GUID, "adventure._active", "adventuresnapshotdirty")
    local _secondary = net_bool(inst.GUID, "adventure._secondary", "adventuresnapshotdirty")
    local _chapter = net_smallbyte(inst.GUID, "adventure._chapter", "adventuresnapshotdirty")
    local _chaptercount = net_smallbyte(inst.GUID, "adventure._chaptercount", "adventuresnapshotdirty")
    local _preset = net_string(inst.GUID, "adventure._preset", "adventuresnapshotdirty")
    local _dirtytask = nil

    local function GetSnapshot()
        if not _active:value() then
            return nil
        end

        local chapter = _chapter:value()
        local chapter_count = _chaptercount:value()
        local preset = _preset:value()
        return
        {
            active = true,
            secondary = _secondary:value(),
            chapter = chapter > 0 and chapter or nil,
            chapter_count = chapter_count > 0 and chapter_count or nil,
            preset = preset ~= "" and preset or nil,
        }
    end

    local function PushSnapshotChanged()
        _world:PushEvent("adventuresnapshotchanged", GetSnapshot())
    end

    local function OnSnapshotDirty()
        if _dirtytask == nil then
            _dirtytask = inst:DoTaskInTime(0, function()
                _dirtytask = nil
                PushSnapshotChanged()
            end)
        end
    end

    function self:SetSnapshot(snapshot)
        if not _ismastersim then
            return
        end

        local active = snapshot ~= nil and snapshot.active == true
        _active:set(active)
        _secondary:set(active and snapshot.secondary == true)
        _chapter:set(active and ClampChapter(snapshot.chapter) or 0)
        _chaptercount:set(active and ClampChapter(snapshot.chapter_count) or 0)
        _preset:set(active and (snapshot.preset or "") or "")
        PushSnapshotChanged()
    end

    function self:GetSnapshot()
        return GetSnapshot()
    end

    function self:IsActive()
        return _active:value()
    end

    function self:IsSecondary()
        return _active:value() and _secondary:value()
    end

    function self:GetChapter()
        local chapter = _chapter:value()
        return _active:value() and chapter > 0 and chapter or nil
    end

    function self:GetChapterCount()
        local chapter_count = _chaptercount:value()
        return _active:value() and chapter_count > 0 and chapter_count or nil
    end

    function self:GetPreset()
        local preset = _preset:value()
        return _active:value() and preset ~= "" and preset or nil
    end

    function self:IsPreset(preset)
        return self:GetPreset() == preset
    end

    function self:GetDebugString()
        local snapshot = GetSnapshot()
        return snapshot ~= nil and string.format(
            "%s chapter %s/%s%s",
            tostring(snapshot.preset),
            tostring(snapshot.chapter),
            tostring(snapshot.chapter_count),
            snapshot.secondary and " (secondary)" or ""
        ) or "inactive"
    end

    function self:OnRemoveFromEntity()
        if _dirtytask ~= nil then
            _dirtytask:Cancel()
            _dirtytask = nil
        end
        if not _ismastersim then
            inst:RemoveEventCallback("adventuresnapshotdirty", OnSnapshotDirty)
        end
    end

    if not _ismastersim then
        inst:ListenForEvent("adventuresnapshotdirty", OnSnapshotDirty)
    end
end)
