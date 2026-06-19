local AddComponentPostInit = AddComponentPostInit
GLOBAL.setfenv(1, GLOBAL)

AddComponentPostInit("worldstate", function(self, inst)
    if self.data.enter_parts_island == nil then
        self.data.enter_parts_island = false
    end

    local _watchers = ToolUtil.GetUpvalue(self.AddWatcher, "_watchers")
    if _watchers == nil then
        print("[worldstate] failed to find _watchers upvalue")
        return
    end

    local function GetFunctionInfo(fn)
        return debug ~= nil and debug.getinfo ~= nil and debug.getinfo(fn, "Sln") or nil
    end

    local function SourceMatches(source, query)
        return query == nil
            or source == query
            or (type(source) == "string" and source:find(query, 1, true) ~= nil)
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

    function self:FindWorldStateWatchFn(var, listener_inst, target, source_query)
        local fallback = nil

        for _, entry in ipairs(self:GetWorldStateWatchEntries(var, listener_inst)) do
            if entry.target == target then
                if SourceMatches(entry.source, source_query) then
                    return entry.fn
                end
                fallback = fallback or entry.fn
            end
        end

        return fallback
    end
end)
