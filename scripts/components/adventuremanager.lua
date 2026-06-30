local PARTS_ISLAND_TAG = "parts_island"
local TWO_LANDS_PRESET = "TWOLANDS"
local PARTS_ISLAND_SEASON_SEGS = { day = 0.7, dusk = 1.6, night = 0.7 }

return Class(function(self, inst)
    self.inst = inst

    local enter_parts_island = false
    local watched_players = {}

    local function IsTwoLands()
        return TheWorld:IsAdventureActive() and ShardGameIndex:GetAdventurePreset() == TWO_LANDS_PRESET
    end

    local function IsPartsIslandArea(area)
        return table.contains(area.tags, PARTS_ISLAND_TAG)
    end

    function self:ApplyTwoLandsPartsIslandWeather()
        local world = TheWorld or inst
        world:PushEvent("ms_setprecipitationmode", "dynamic")
        world:PushEvent("ms_setmoisturescale", 2)
        world:PushEvent("ms_forceprecipitation", true)
        world:PushEvent("ms_setseasonsegmodifier", PARTS_ISLAND_SEASON_SEGS)
    end

    local function TriggerTwoLandsPartsIsland(player)
        inst:PushEvent("enter_parts_island", { player = player, area = PARTS_ISLAND_TAG })

        if enter_parts_island then
            return
        end

        enter_parts_island = true
        self:ApplyTwoLandsPartsIslandWeather()
    end

    local function OnPlayerAreaChanged(player, area)
        if IsTwoLands() and IsPartsIslandArea(area) then
            TriggerTwoLandsPartsIsland(player)
        end
    end

    local function CheckPlayerArea(player)
        if player == nil or not player:IsValid() or player.components == nil or player.components.areaaware == nil then
            return
        end

        local x, y, z = player.Transform:GetWorldPosition()
        player.components.areaaware:UpdatePosition(x, y, z)
        OnPlayerAreaChanged(player, player.components.areaaware:GetCurrentArea())
    end

    local function WatchPlayer(player)
        if player == nil or watched_players[player] then
            return
        end

        watched_players[player] = true
        player:ListenForEvent("changearea", OnPlayerAreaChanged)
        inst:DoTaskInTime(0, function()
            CheckPlayerArea(player)
        end)
    end

    local function StopWatchingPlayer(player)
        if player ~= nil then
            watched_players[player] = nil
            player:RemoveEventCallback("changearea", OnPlayerAreaChanged)
        end
    end

    local function OnPlayerJoined(world, player)
        WatchPlayer(player)
    end

    local function OnPlayerLeft(world, player)
        StopWatchingPlayer(player)
    end

    for _, player in ipairs(AllPlayers) do
        WatchPlayer(player)
    end

    inst:ListenForEvent("ms_playerjoined", OnPlayerJoined)
    inst:ListenForEvent("ms_playerleft", OnPlayerLeft)

    function self:IsTwoLands()
        return IsTwoLands()
    end

    function self:HasEnteredPartsIsland()
        return enter_parts_island
    end

    function self:WatchPlayer(player)
        WatchPlayer(player)
    end

    function self:StopWatchingPlayer(player)
        StopWatchingPlayer(player)
    end

    function self:OnSave()
        return {
            enter_parts_island = enter_parts_island == true,
        }
    end

    function self:OnLoad(data)
        enter_parts_island = data ~= nil and data.enter_parts_island == true
        if enter_parts_island then
            inst:DoTaskInTime(0, function()
                self:ApplyTwoLandsPartsIslandWeather()
            end)
        end
    end

    function self:OnRemoveFromEntity()
        inst:RemoveEventCallback("ms_playerjoined", OnPlayerJoined)
        inst:RemoveEventCallback("ms_playerleft", OnPlayerLeft)

        for player in pairs(watched_players) do
            StopWatchingPlayer(player)
        end
    end
end)
