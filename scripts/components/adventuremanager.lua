local PARTS_ISLAND_TAG = "parts_island"
local PARTS_ISLAND_SEASON_SEGS = { day = 0.7, dusk = 1.6, night = 0.7 }

return Class(function(self, inst)
    self.inst = inst

    local enter_parts_island = false
    local watched_players = {}

    local function ApplyTwoLandsPartsIslandWeather()
        inst:PushEvent("ms_setprecipitationmode", "dynamic")
        inst:PushEvent("ms_setmoisturescale", 2)
        inst:PushEvent("ms_forceprecipitation", true)
        inst:PushEvent("ms_setseasonsegmodifier", PARTS_ISLAND_SEASON_SEGS)
    end

    local function TriggerTwoLandsPartsIsland(player)
        inst:PushEvent("enter_parts_island", { player = player, area = PARTS_ISLAND_TAG })

        if enter_parts_island then
            return
        end

        enter_parts_island = true
        ApplyTwoLandsPartsIslandWeather()
    end

    local function OnPlayerAreaChanged(player, area)
        if TheWorld:IsAdventurePreset("TWOLANDS") and table.contains(area.tags, PARTS_ISLAND_TAG) then
            TriggerTwoLandsPartsIsland(player)
        end
    end

    local function CheckPlayerArea(player)
        if not player:IsValid() then
            return
        end

        local x, y, z = player.Transform:GetWorldPosition()
        player.components.areaaware:UpdatePosition(x, y, z)
        OnPlayerAreaChanged(player, player.components.areaaware:GetCurrentArea())
    end

    local function WatchPlayer(player)
        if watched_players[player] then
            return
        end

        watched_players[player] = true
        player:ListenForEvent("changearea", OnPlayerAreaChanged)
        inst:DoTaskInTime(0, function()
            CheckPlayerArea(player)
        end)
    end

    local function StopWatchingPlayer(player)
        watched_players[player] = nil
        player:RemoveEventCallback("changearea", OnPlayerAreaChanged)
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

    function self:OnSave()
        return {
            enter_parts_island = enter_parts_island == true,
        }
    end

    function self:OnLoad(data)
        enter_parts_island = data ~= nil and data.enter_parts_island == true
        if enter_parts_island then
            inst:DoTaskInTime(0, function()
                ApplyTwoLandsPartsIslandWeather()
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
