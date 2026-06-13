local AddPrefabPostInit = AddPrefabPostInit
GLOBAL.setfenv(1, GLOBAL)

AddPrefabPostInit("diviningrod", function(inst)
    if not TheWorld.ismastersim then
        return
    end

    local _CheckTargetPiece, scope_fn, i = ToolUtil.GetUpvalue(inst.components.equippable.onequipfn, "CheckTargetPiece")
    local CheckTargetPiece = function(inst)
        local ret = { _CheckTargetPiece(inst) }

        -- Huh?
        if inst.components.equippable:IsEquipped() and inst.components.inventoryitem.owner then
            inst.SoundEmitter:KillSound("ping")
        end

        return unpack(ret)
    end

    if i then
        debug.setupvalue(scope_fn, i, _CheckTargetPiece)
    end
end)