local AdventureManager = Class(function(self, inst)
    self.inst = inst
    self.enter_parts_island = false
    self._onplayerjoined = function(world, player) self:WatchPlayer(player) end
    self._onplayerleft = function(world, player) self:StopWatchingPlayer(player) end
    self._onplayerchangearea = function(player, area) self:OnPlayerAreaChanged(player, area) end
    self._watched_players = {}

    inst:ListenForEvent("ms_playerjoined", self._onplayerjoined)
    inst:ListenForEvent("ms_playerleft", self._onplayerleft)
end)

local function GetAdventurePreset()
    local state = ShardGameIndex ~= nil and ShardGameIndex:GetAdventureState() or nil
    local preset = state ~= nil and state.current_preset or nil

    if type(preset) == "table" then
        preset = preset.id or preset.worldgen_preset or preset.preset
    end

    return preset
end

function AdventureManager:IsActive()
    return ShardGameIndex ~= nil and ShardGameIndex:IsAdventureActive()
end

function AdventureManager:IsTwoLands()
    return self:IsActive() and GetAdventurePreset() == "TWOLANDS"
end

function AdventureManager:ApplyTwoLandsPartsIslandWeather()
    self.inst:PushEvent("ms_setprecipitationmode", "dynamic")
    self.inst:PushEvent("ms_setmoisturescale", 2)
    self.inst:PushEvent("ms_forceprecipitation", true)
    self.inst:PushEvent("ms_setseasonsegmodifier", { day = 0.7, dusk = 1.6, night = 0.7 })
end

function AdventureManager:TriggerTwoLandsPartsIsland(player)
    self.inst:PushEvent("enter_parts_island", { player = player, area = "parts_island" })

    if self.enter_parts_island then
        return
    end

    self.enter_parts_island = true
    self:ApplyTwoLandsPartsIslandWeather()
end

function AdventureManager:OnPlayerAreaChanged(player, area)
    if self:IsTwoLands() and type(area) == "table" and table.contains(area, "parts_island") then
        self:TriggerTwoLandsPartsIsland(player)
    end
end

function AdventureManager:CheckPlayerArea(player)
    if player == nil or not player:IsValid() or player.components == nil or player.components.areaaware == nil then
        return
    end

    player.components.areaaware:UpdatePosition(player.Transform:GetWorldPosition())
    self:OnPlayerAreaChanged(player, player.components.areaaware:GetCurrentArea())
end

function AdventureManager:WatchPlayer(player)
    if player == nil then
        return
    end

    if self._watched_players[player] then
        return
    end

    self._watched_players[player] = true
    player:ListenForEvent("changearea", self._onplayerchangearea)
    self.inst:DoTaskInTime(0, function()
        self:CheckPlayerArea(player)
    end)
end

function AdventureManager:StopWatchingPlayer(player)
    if player ~= nil then
        self._watched_players[player] = nil
        player:RemoveEventCallback("changearea", self._onplayerchangearea)
    end
end

function AdventureManager:WatchExistingPlayers()
    if AllPlayers == nil then
        return
    end

    for _, player in ipairs(AllPlayers) do
        self:WatchPlayer(player)
    end
end

function AdventureManager:OnSave()
    return {
        enter_parts_island = self.enter_parts_island == true,
    }
end

function AdventureManager:OnLoad(data)
    self.enter_parts_island = data ~= nil and data.enter_parts_island == true
    if self.enter_parts_island then
        self.inst:DoTaskInTime(0, function()
            self:ApplyTwoLandsPartsIslandWeather()
        end)
    end
end

function AdventureManager:OnRemoveFromEntity()
    self.inst:RemoveEventCallback("ms_playerjoined", self._onplayerjoined)
    self.inst:RemoveEventCallback("ms_playerleft", self._onplayerleft)

    if AllPlayers ~= nil then
        for _, player in ipairs(AllPlayers) do
            self:StopWatchingPlayer(player)
        end
    end
end

return AdventureManager
