GLOBAL.setfenv(1, GLOBAL)

if not rawget(_G, "c_revealmap") then
    function c_revealmap()
        local size = 2 * TheWorld.Map:GetSize()
        local player = ConsoleCommandPlayer()
        for x = -size, size, 32 do
            for z = -size, size, 32 do
                player.player_classified.MapExplorer:RevealArea(x, 0, z)
            end
        end
    end
end

function c_debug()
    local player = ConsoleCommandPlayer()
    c_supergodmode(player)
    c_select(player)
    c_freecrafting(player)
end

function c_giveparts()
    c_give("teleportato_ring")
    c_give("teleportato_box")
    c_give("teleportato_crank")
    c_give("teleportato_potato")
end

function c_adventure_last()
    if ShardGameIndex == nil or ShardGameIndex.GetAdventureState == nil then
        print("[Adventure Mode] Adventure state is unavailable.")
        return false
    end

    if ShardGameIndex.IsMasterShard ~= nil and not ShardGameIndex:IsMasterShard() then
        print("[Adventure Mode] c_adventure_last must be called on the master shard.")
        return false
    end

    local state = ShardGameIndex:GetAdventureState()
    local total = state ~= nil and state.level_sequence ~= nil and #state.level_sequence or 0
    if state == nil or not state.active or total <= 0 then
        print("[Adventure Mode] No active adventure to jump.")
        return false
    end

    local chapter = state.chapter or 1
    if chapter >= total then
        print("[Adventure Mode] Already at the final chapter.")
        return false
    end

    print("[Adventure Mode] Jumping from chapter "..tostring(chapter).." to chapter "..tostring(total)..".")
    return AdvanceShardAdventure({ chapter = total })
end

function c_frograin()
    TheWorld.components.frograin:StartFrogRain()
end
