local AddStategraphState = AddStategraphState
GLOBAL.setfenv(1, GLOBAL)

local function MakeSleepState(server_states)
    return State{
        name = "sleep",
        tags = { "busy", "sleeping", "nopredict", "nomorph" },
        server_states = server_states,

        onenter = function(inst)
            if inst.components.locomotor ~= nil then
                inst.components.locomotor:Stop()
                inst.components.locomotor:StopMoving()
            end
            if inst.ClearBufferedAction ~= nil then
                inst:ClearBufferedAction()
            end
            inst.AnimState:PlayAnimation("sleep")
            if inst.components.playercontroller ~= nil then
                inst.components.playercontroller:EnableMapControls(false)
                inst.components.playercontroller:Enable(false)
            end
            if inst.components.health ~= nil then
                inst.sg.statemem.was_invincible = inst.components.health.invincible
                inst.components.health:SetInvincible(true)
            end
            if inst.components.inventory ~= nil then
                inst.components.inventory:Hide()
            end
            if inst.ShowActions ~= nil then
                inst:ShowActions(false)
            end
        end,

        onexit = function(inst)
            if inst.components.health ~= nil then
                inst.components.health:SetInvincible(inst.sg.statemem.was_invincible == true)
            end
            if inst.components.inventory ~= nil then
                inst.components.inventory:Show()
            end
            if inst.ShowActions ~= nil then
                inst:ShowActions(true)
            end
            if inst.components.playercontroller ~= nil then
                inst.components.playercontroller:EnableMapControls(true)
                inst.components.playercontroller:Enable(true)
            end
        end,
    }
end

local states =
{
    MakeSleepState(),
}

for _, state in ipairs(states) do
    AddStategraphState("wilson", state)
end

local client_states =
{
    MakeSleepState({ "sleep" }),
}

for _, state in ipairs(client_states) do
    AddStategraphState("wilson_client", state)
end
