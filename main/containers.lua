GLOBAL.setfenv(1, GLOBAL)

local containers = require("containers")

local params = containers.params

local function GetTeleportatoBase(inst)
    if inst == nil then
        return nil
    end

    local teleportato = inst._base
    if teleportato == nil and inst._teleportato_base ~= nil then
        teleportato = inst._teleportato_base:value()
    end
    return teleportato ~= nil and teleportato:IsValid() and teleportato or nil
end

params.teleportato_player_container = deepcopy(params.teleportato_base)
if params.teleportato_player_container ~= nil and params.teleportato_player_container.widget ~= nil then
    params.teleportato_player_container.itemtestfn = function(container, item, slot)
        return not item:HasTag("nonpotatable") and not item:HasTag("bundle")
    end
    params.teleportato_player_container.widget.buttoninfo =
    {
        text = STRINGS.ACTIONS.ACTIVATE.GENERIC,
        position = Vector3(0, -165, 0),
        fn = function(inst, doer)
            if inst.components.container ~= nil then
                local teleportato = GetTeleportatoBase(inst)
                if teleportato ~= nil and type(teleportato.CheckNextLevelSure) == "function" then
                    teleportato:CheckNextLevelSure(doer)
                end
            elseif inst.replica.container ~= nil and not inst.replica.container:IsBusy() then
                SendRPCToServer(RPC.DoWidgetButtonAction, ACTIONS.ACTIVATE_CONTAINER.code, inst, ACTIONS.ACTIVATE_CONTAINER.mod_name)
            end
        end,
        validfn = function(inst)
            return inst ~= nil and inst.replica.container ~= nil
        end,
    }
end

if params.teleportato_base ~= nil and params.teleportato_base.widget ~= nil then
    params.teleportato_base.widget.buttoninfo = nil
end
