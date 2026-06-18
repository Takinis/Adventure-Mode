local AddStategraphState = AddStategraphState
GLOBAL.setfenv(1, GLOBAL)

local function MakeSleepState()
    return State{
        name = "sleep",

        onenter = function(inst)
            inst.AnimState:PlayAnimation("sleep")
            if inst.components.playercontroller ~= nil then
                inst.components.playercontroller:Enable(false)
            end
            if inst.components.health ~= nil then
                inst.components.health:SetInvincible(true)
            end
        end,

        onexit = function(inst)
            if inst.components.health ~= nil then
                inst.components.health:SetInvincible(false)
            end
            if inst.components.playercontroller ~= nil then
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
    MakeSleepState(),
}

for _, state in ipairs(client_states) do
    AddStategraphState("wilson_client", state)
end
