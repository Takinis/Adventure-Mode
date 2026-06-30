local MAX_SYNCED_CHAPTER = 63

local function GetPresetId(preset)
    if type(preset) == "table" then
        return preset.id or preset.worldgen_preset or preset.preset or preset.settings_preset
    end
    return preset
end

local function BuildClientState(state)
    if state == nil then
        return nil
    end

    local total_chapters = type(state.level_sequence) == "table" and #state.level_sequence or nil

    return
    {
        active = state.active == true,
        secondary = state.secondary == true or nil,
        reason = state.reason,
        sequence_id = state.sequence_id,
        chapter = state.chapter,
        current_preset = GetPresetId(state.current_preset),
        current_session_id = state.current_session_id,
        total_chapters = total_chapters,
        started_at = state.started_at,
        updated_at = state.updated_at,
        finished_at = state.finished_at,
        return_reason = state.return_reason,
    }
end

return Class(function(self, inst)
    self.inst = inst

    local _world = TheWorld
    local _ismastersim = _world.ismastersim

    local _active = net_bool(inst.GUID, "adventurestate._active", "adventurestatedirty")
    local _secondary = net_bool(inst.GUID, "adventurestate._secondary", "adventurestatedirty")
    local _chapter = net_smallbyte(inst.GUID, "adventurestate._chapter", "adventurestatedirty")
    local _totalchapters = net_smallbyte(inst.GUID, "adventurestate._totalchapters", "adventurestatedirty")
    local _currentpreset = net_string(inst.GUID, "adventurestate._currentpreset", "adventurestatedirty")
    local _clientstate = nil

    local function PushAdventureStateDirty()
        _world:PushEvent("adventurestatedirty", _clientstate)
    end

    local function DecodeState()
        if not _active:value() then
            _clientstate = nil
            PushAdventureStateDirty()
            return nil
        end

        local chapter = _chapter:value()
        local total_chapters = _totalchapters:value()
        _clientstate =
        {
            active = true,
            secondary = _secondary:value() or nil,
            chapter = chapter > 0 and chapter or nil,
            total_chapters = total_chapters > 0 and total_chapters or nil,
            current_preset = _currentpreset:value() ~= "" and _currentpreset:value() or nil,
        }
        PushAdventureStateDirty()
        return _clientstate
    end

    local function SetState(state)
        local client_state = BuildClientState(state)
        _clientstate = client_state

        if client_state ~= nil and client_state.active then
            _active:set(true)
            _secondary:set(client_state.secondary == true)
            _chapter:set(math.clamp(client_state.chapter or 0, 0, MAX_SYNCED_CHAPTER))
            _totalchapters:set(math.clamp(client_state.total_chapters or 0, 0, MAX_SYNCED_CHAPTER))
            _currentpreset:set(client_state.current_preset or "")
        else
            _active:set(false)
            _secondary:set(false)
            _chapter:set(0)
            _totalchapters:set(0)
            _currentpreset:set("")
        end

        PushAdventureStateDirty()
    end

    local function OnAdventureStateDirty()
        DecodeState()
    end

    function self:SetState(state)
        if _ismastersim then
            SetState(state)
        end
    end

    function self:GetState()
        return _ismastersim and BuildClientState(ShardGameIndex.adventure:GetState())
            or _clientstate
    end

    function self:IsActive()
        if _ismastersim then
            local state = self:GetState()
            return state ~= nil and state.active == true
        end
        return _active:value()
    end

    if _ismastersim then
        SetState(ShardGameIndex.adventure:GetState())
    else
        inst:ListenForEvent("adventurestatedirty", OnAdventureStateDirty)
        DecodeState()
    end
end)
