GLOBAL.setfenv(1, GLOBAL)

local containers = require("containers")

local params = containers.params
if params.teleportato_base ~= nil and params.teleportato_base.widget ~= nil then
    params.teleportato_base.widget.buttoninfo =
    {
        text = STRINGS.ACTIONS.ACTIVATE.GENERIC,
        position = Vector3(0, -165, 0),
        fn = function(inst, doer)
            if inst.components.container ~= nil then
                BufferedAction(doer, inst, ACTIONS.ACTIVATE_CONTAINER):Do()
            elseif inst.replica.container ~= nil and not inst.replica.container:IsBusy() then
                SendRPCToServer(RPC.DoWidgetButtonAction, ACTIONS.ACTIVATE_CONTAINER.code, inst, ACTIONS.ACTIVATE_CONTAINER.mod_name)
            end
        end,
        validfn = function(inst)
            return inst ~= nil and inst.replica.container ~= nil and inst.replica.container:IsOpenedBy(ThePlayer)
        end,
    }
end
