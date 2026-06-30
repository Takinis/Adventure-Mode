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

-- local REPLACE_COMPONENTS =
-- {
--     ["frograin"] = {
--         testfn = function()
--             return ShardGameIndex.adventure:IsActive()
--         end,
--         target_cmp = "ad_frograin",
--     },
-- }
-- local _AddComponent = EntityScript.AddComponent
-- function EntityScript:AddComponent(cmp_name, ...)
--     if REPLACE_COMPONENTS[cmp_name] and REPLACE_COMPONENTS[cmp_name].testfn(cmp_name) then
--         return _AddComponent(self, REPLACE_COMPONENTS[cmp_name].target_cmp, ...)
--     end
--     return _AddComponent(self, cmp_name, ...)
-- end