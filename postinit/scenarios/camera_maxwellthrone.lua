local camera_maxwellthrone = require "scenarios/camera_maxwellthrone"
GLOBAL.setfenv(1, GLOBAL)

camera_maxwellthrone.OnLoad = function(inst, scenariorunner)
    if inst ~= nil and inst.StartCameraController ~= nil then
        inst:StartCameraController()
    end
end

camera_maxwellthrone.OnDestroy = function(inst, scenariorunner)
    if inst ~= nil and inst.StopCameraController ~= nil then
        inst:StopCameraController()
    end
end
