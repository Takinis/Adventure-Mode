local camera_maxwellthrone = require "scenarios/camera_maxwellthrone"
GLOBAL.setfenv(1, GLOBAL)

camera_maxwellthrone.OnLoad = function(inst, scenariorunner)
    inst:StartCameraController()
end

camera_maxwellthrone.OnDestroy = function(inst, scenariorunner)
    inst:StopCameraController()
end
