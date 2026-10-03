local AddPrefabPostInit = AddPrefabPostInit
GLOBAL.setfenv(1, GLOBAL)

local SIGN_TEXT = "你不应该来这里。"

AddPrefabPostInit("homesign", function(inst)
    if not TheWorld.ismastersim then
        return
    end

    local topology = TheWorld.topology
    local overrides = topology ~= nil and topology.overrides or nil
    if overrides ~= nil and (overrides.task_set == "HAMLET_SECONDARY" or overrides.task_set == "ADVENTURE_SECONDARY") then
        if inst.components.writeable:GetText() == nil then
            inst.components.writeable:SetText(SIGN_TEXT)
        end
    end
end)
