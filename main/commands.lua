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

function c_frograin()
    TheWorld.components.frograin:StartFrogRain()
end