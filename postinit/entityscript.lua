GLOBAL.setfenv(1, GLOBAL)

-- GetEventCallbacks from Porkland, No modifications were made.
---@param event string
---@param source entityscript | nil
---@param source_file string | nil
function EntityScript:GetEventCallbacks(event, source, source_file, test_fn)
    source = source or self

    if not self.event_listening[event] or not self.event_listening[event][source] then
        return
    end

    for _, fn in ipairs(self.event_listening[event][source]) do
        if source_file then
            local info = debug.getinfo(fn, "S")
            if info and (info.source == source_file) and (not test_fn or test_fn(fn)) then
                return fn
            end
        elseif (not test_fn or test_fn(fn)) then
            return fn
        end
    end
end