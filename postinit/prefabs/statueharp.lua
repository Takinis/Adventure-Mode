local AddPrefabPostInit = AddPrefabPostInit
GLOBAL.setfenv(1, GLOBAL)

AddPrefabPostInit("statueharp", function(inst)

    if not TheWorld.ismastersim then
        return
    end

    if TheWorld.is_adventure then
        inst.charlie_test = true
    end

    local _invokecharliesanger, scope_fn, i = ToolUtil.GetUpvalue(inst.OnLoad, "invokecharliesanger")
    local invokecharliesanger = function(inst)
        if TheWorld.is_adventure then
            return
        end

        _invokecharliesanger(inst)
    end

    if i then
        debug.setupvalue(scope_fn, i, invokecharliesanger)
    end
end)