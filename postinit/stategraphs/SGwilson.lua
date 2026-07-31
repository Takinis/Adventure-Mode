local AddStategraphState = AddStategraphState
GLOBAL.setfenv(1, GLOBAL)

local function MakeAdventureIntroState(server_states)
    return State{
        name = "adventure_intro",
        tags = { "busy", "sleeping", "nopredict", "nomorph", "noattack", "nointerrupt", "temp_invincible" },
        server_states = server_states,

        onenter = function(inst)
            if inst.components.locomotor ~= nil then
                inst.components.locomotor:Stop()
                inst.components.locomotor:StopMoving()
            end
            inst:ClearBufferedAction()
            inst.AnimState:PlayAnimation("sleep")
            if inst.components.playercontroller ~= nil then
                inst.sg.statemem.controller_enabled =
                    inst.components.playercontroller.classified ~= nil and
                    inst.components.playercontroller.classified.iscontrollerenabled:value()
                inst.sg.statemem.map_enabled = inst.components.playercontroller.is_map_enabled
                inst.components.playercontroller:EnableMapControls(false)
                inst.components.playercontroller:Enable(false)
            end
            if inst.components.inventory ~= nil then
                inst.sg.statemem.inventory_visible = inst.components.inventory.isvisible
                inst.components.inventory:Hide()
            end
            inst.sg.statemem.actions_visible = inst:IsActionsVisible()
            inst:ShowActions(false)
            if inst.components.grue ~= nil then
                inst.components.grue:AddImmunity("adventure_intro")
            end
        end,

        onexit = function(inst)
            if inst.components.grue ~= nil then
                inst.components.grue:RemoveImmunity("adventure_intro")
            end
            if inst.components.inventory ~= nil and inst.sg.statemem.inventory_visible then
                inst.components.inventory:Show()
            end
            inst:ShowActions(inst.sg.statemem.actions_visible == true)
            if inst.components.playercontroller ~= nil then
                inst.components.playercontroller:EnableMapControls(inst.sg.statemem.map_enabled == true)
                inst.components.playercontroller:Enable(inst.sg.statemem.controller_enabled == true)
            end
        end,
    }
end

local states =
{
    MakeAdventureIntroState(),
}

for _, state in ipairs(states) do
    AddStategraphState("wilson", state)
end

local client_states =
{
    MakeAdventureIntroState({ "adventure_intro" }),
}

for _, state in ipairs(client_states) do
    AddStategraphState("wilson_client", state)
end
