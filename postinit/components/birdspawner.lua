local BirdSpawner = require("components/birdspawner")
local AddComponentPostInit = AddComponentPostInit
GLOBAL.setfenv(1, GLOBAL)

AddComponentPostInit("birdspawner", function(self, inst)
    local _is_adventure_active = ShardGameIndex:IsAdventureActive()
    local _GetSpawnPoint = self.GetSpawnPoint
    function self:GetSpawnPoint(pt, is_corpse)
        local spawnpoint = _GetSpawnPoint(self, pt, is_corpse)
        if _is_adventure_active then
            local x, y, z = spawnpoint:Get()
            if TheWorld.Map:IsOceanAtPoint(x, y, z, false)
                and TheWorld.Map:GetPlatformAtPoint(x, z) == nil then
                return nil
            end
        end
        return spawnpoint
    end
end)