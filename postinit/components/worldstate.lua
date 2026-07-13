local AddComponentPostInit = AddComponentPostInit
GLOBAL.setfenv(1, GLOBAL)

local RAINY_WORLD_PRECIPITATION_MULT = 3

local function SourceMatches(source, query)
    return query == nil
        or source == query
        or (type(source) == "string" and source:find(query, 1, true) ~= nil)
end

AddComponentPostInit("worldstate", function(self, inst)
    local _watchers = ToolUtil.GetUpvalue(self.AddWatcher, "_watchers")
    if _watchers == nil then
        print("[worldstate] failed to find _watchers upvalue")
        return
    end

    local OnWeatherTick = inst:GetEventCallbacks("weathertick", nil, "scripts/components/ToolUtil.lua")
    if OnWeatherTick ~= nil then
        inst:RemoveEventCallback("weathertick", OnWeatherTick)
        inst:ListenForEvent("weathertick", function(src, data)
            if TheWorld:IsAdventureLevel("RAINY") and
                data ~= nil and
                self.data.israining and
                data.precipitationrate ~= nil and
                data.precipitationrate > 0 then
                local boosted = {}
                for k, v in pairs(data) do
                    boosted[k] = v
                end
                boosted.precipitationrate = data.precipitationrate * RAINY_WORLD_PRECIPITATION_MULT
                OnWeatherTick(src, boosted)
            else
                OnWeatherTick(src, data)
            end
        end)
    else
        print("[worldstate] failed to find weathertick listener")
    end

    local function GetFunctionInfo(fn)
        return debug ~= nil and debug.getinfo(fn, "Sln") or nil
    end

    local BuildCallbackEntry

    local function BuildListenerEntry(listener_inst, var, watcherfns)
        local entry = {
            inst = listener_inst,
            target = nil,
            fns = {},
            entries = {},
        }

        for i, raw in ipairs(watcherfns) do
            local callback = BuildCallbackEntry(raw[1], raw[2], i, listener_inst, var)
            entry.target = entry.target or callback.target
            table.insert(entry.fns, callback.fn)
            table.insert(entry.entries, callback)
        end

        return entry
    end

    BuildCallbackEntry = function(fn, target, index, listener_inst, var)
        local info = GetFunctionInfo(fn) or {}
        return {
            fn          = fn,
            target      = target,
            inst        = listener_inst,
            var         = var,
            source      = info.source,
            short_src   = info.short_src,
            linedefined = info.linedefined,
            lastlinedefined = info.lastlinedefined,
            name        = info.name,
            namewhat    = info.namewhat,
            what        = info.what,
            index       = index,
        }
    end

    function self:GetWorldStateWatchFns(var, listener_inst)
        local watchers = _watchers[var]
        if watchers == nil then
            return {}
        end

        if listener_inst ~= nil then
            local watcherfns = watchers[listener_inst]
            local out = {}
            if watcherfns ~= nil then
                for _, raw in ipairs(watcherfns) do
                    table.insert(out, raw[1])
                end
            end
            return out
        end

        local out = {}
        for watcher_inst, watcherfns in pairs(watchers) do
            table.insert(out, BuildListenerEntry(watcher_inst, var, watcherfns))
        end
        return out
    end

    function self:GetWorldStateWatchEntries(var, listener_inst)
        local watchers = _watchers[var]
        local out = {}
        if watchers == nil then
            return out
        end

        if listener_inst ~= nil then
            local watcherfns = watchers[listener_inst]
            if watcherfns ~= nil then
                for i, raw in ipairs(watcherfns) do
                    table.insert(out, BuildCallbackEntry(raw[1], raw[2], i, listener_inst, var))
                end
            end
            return out
        end

        for watcher_inst, watcherfns in pairs(watchers) do
            for i, raw in ipairs(watcherfns) do
                table.insert(out, BuildCallbackEntry(raw[1], raw[2], i, watcher_inst, var))
            end
        end
        return out
    end

    function self:GetWorldStateWatchFn(var, listener_inst, target, source_query, test_fn)
        local fallback = nil

        for _, entry in ipairs(self:GetWorldStateWatchEntries(var, listener_inst)) do
            if target == nil or entry.target == target then
                local source_match = source_query ~= nil and SourceMatches(entry.source, source_query)
                local test_match = test_fn ~= nil and test_fn(entry.fn, entry)

                if source_match or test_match then
                    return entry.fn
                elseif source_query == nil and test_fn == nil then
                    fallback = fallback or entry.fn
                end
            end
        end

        local watcherfns = listener_inst ~= nil
            and listener_inst.worldstatewatching ~= nil
            and listener_inst.worldstatewatching[var]
            or nil
        if watcherfns ~= nil and (source_query ~= nil or test_fn ~= nil) then
            for i, fn in ipairs(watcherfns) do
                if type(fn) == "function" then
                    local entry = BuildCallbackEntry(fn, nil, i, listener_inst, var)
                    local source_match = source_query ~= nil and SourceMatches(entry.source, source_query)
                    local test_match = test_fn ~= nil and test_fn(entry.fn, entry)

                    if source_match or test_match then
                        return entry.fn
                    end
                end
            end
        end

        return fallback
    end

    function self:FindWorldStateWatchFn(...)
        return self:GetWorldStateWatchFn(...)
    end
end)
