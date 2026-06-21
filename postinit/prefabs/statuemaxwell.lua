local AddPrefabPostInit = AddPrefabPostInit
GLOBAL.setfenv(1, GLOBAL)

AddPrefabPostInit("statuemaxwell", function(inst)

    if not TheWorld.ismastersim then
        return
    end

    local _statuemaxwell_fn = Prefabs["statuemaxwell"].fn
    local _doCharlieTest, scope_fn, i = ToolUtil.GetUpvalue(_statuemaxwell_fn, "doCharlieTest")
    local doCharlieTest = function(inst)
        if ShardGameIndex:IsAdventureActive() then
            return
        end

        _doCharlieTest(inst)
    end

    if i then
        debug.setupvalue(scope_fn, i, doCharlieTest)
    end
end)