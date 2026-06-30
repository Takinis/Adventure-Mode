local AddPrefabPostInit = AddPrefabPostInit
GLOBAL.setfenv(1, GLOBAL)

AddPrefabPostInit("statueharp", function(inst)

    if not TheWorld.ismastersim then
        return
    end

    -- local _statueharp_fn = Prefabs["statueharp"].fn
    -- local _doCharlieTest, scope_fn, i = ToolUtil.GetUpvalue(_statueharp_fn, "doCharlieTest")
    -- local doCharlieTest = function(inst)
    --     if ShardGameIndex.adventure:IsActive() then
    --         return
    --     end

    --     _doCharlieTest(inst)
    -- end

    -- if i then
    --     debug.setupvalue(scope_fn, i, doCharlieTest)
    -- end

    if ShardGameIndex.adventure:IsActive() then
        inst.charlie_test = true
    end

    local _invokecharliesanger, scope_fn, i = ToolUtil.GetUpvalue(inst.OnLoad, "invokecharliesanger")
    local invokecharliesanger = function(inst)
        if ShardGameIndex.adventure:IsActive() then
            return
        end

        _invokecharliesanger(inst)
    end

    if i then
        debug.setupvalue(scope_fn, i, invokecharliesanger)
    end
end)