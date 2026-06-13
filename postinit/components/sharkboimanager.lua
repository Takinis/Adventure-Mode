local AddComponentPostInit = AddComponentPostInit
GLOBAL.setfenv(1, GLOBAL)

AddComponentPostInit("sharkboimanager", function(self, inst)
    if not ShardGameIndex:IsAdventureActive() then
        return
    end

    if self.InitializeSharkBoiManager ~= nil then
        inst:RemoveEventCallback("worldmapsetsize", self.InitializeSharkBoiManager, TheWorld)
    end

    if self.OnSeasonChange ~= nil then
        self:StopWatchingWorldState("season", self.OnSeasonChange)
    end

    self.InitializeSharkBoiManager = function() end
    self.OnSeasonChange = function() end
    self.OnCooldownEnd = function()
        self:ForceCleanup()
        self.arena = nil
    end

    function self:CreateFishingHole()
        return nil
    end

    function self:ArenaFinishCreating()
        self.arena.fishinghole = nil
        self:StartEventListeners()
        TheWorld:PushEvent("ms_spawnedsharkboiarena", self.arena)
    end

    function self:FindAndPlaceOceanArenaOverTime()
        self:StopFindAndPlaceOceanArenaOverTime()
    end

    function self:TryToPlaceOceanArena()
        return false
    end

    function self:PlaceOceanArenaAtPosition()
        return false
    end

    function self:OnLoad(data)
        if data == nil then
            return
        end

        self:StopFindAndPlaceOceanArenaOverTime()
        self.arena = nil
    end

    function self:LoadPostPass()
    end

    function self:OnSave()
        return nil
    end
end)
