local AddComponentPostInit = AddComponentPostInit
GLOBAL.setfenv(1, GLOBAL)

AddComponentPostInit("wavemanager", function(self)
	if ShardGameIndex:IsAdventureActive() then
		self.OnUpdate = function() end
    end
end)