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
    if ShardGameIndex == nil or ShardGameIndex.adventure == nil then
        print("[Adventure Mode] Adventure state is unavailable.")
        return false
    end

    if not ShardGameIndex.adventure:IsMasterShard() then
        print("[Adventure Mode] c_adventure_last must be called on the master shard.")
        return false
    end

    local state = ShardGameIndex.adventure:GetState()
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
    return ShardGameIndex.adventure:AdvanceShard({ chapter = total })
end

local WORLD_SWITCH_WORLD_ALIASES =
{
    dst = "forest",
    forest = "forest",
    cave = "cave",
    caves = "cave",
    sw = "shipwrecked",
    shipwrecked = "shipwrecked",
    volcano = "volcano",
    hamlet = "porkland",
    porkland = "porkland",
}

local function GetConsoleWorldSwitchIndex()
    if ShardGameIndex == nil or ShardGameIndex.worldindex == nil then
        print("[Shard World Index] ShardWorldIndex is unavailable.")
        return nil
    end
    return ShardGameIndex.worldindex
end

local function GetConsoleWorldSwitchTarget(world_type)
    if type(world_type) == "table" then
        return world_type, world_type.file_id or world_type.world_type or world_type.location or world_type.id or world_type.session_id
    end

    if world_type == nil or world_type == "" then
        print("[Shard World Index] Usage: c_switchworld(\"porkland\"), c_shipwrecked(), c_volcano(), c_porkland(), c_forestworld().")
        return nil
    end

    local key = string.lower(tostring(world_type))
    local target_world_type = WORLD_SWITCH_WORLD_ALIASES[key] or key
    return { type = "generated", world_type = target_world_type }, target_world_type
end

local function IsConsoleAdventureWorldSwitchActive(index)
    local state = index:GetState()
    return state ~= nil and state.active == true and state.kind == "adventure"
end

function c_switchworld(world_type)
    local index = GetConsoleWorldSwitchIndex()
    if index == nil then
        return false
    end

    if IsConsoleAdventureWorldSwitchActive(index) then
        print("[Shard World Index] Adventure is active; c_switchworld is only for normal world switching.")
        return false
    end

    local target, file_id = GetConsoleWorldSwitchTarget(world_type)
    if target == nil then
        return false
    end

    local opts =
    {
        kind = "world_switch",
        reason = "console_switch",
        target = target,
        file_id = file_id,
        reuse_existing = true,
        force_players_to_master_modname = "AdventureMode",
        force_players_to_master_rpcname = "ForcePlayersToMaster",
    }

    if index:IsActive() then
        opts.reason = "console_advance"
        print("[Shard World Index] Advancing to "..tostring(file_id or world_type)..".")
        return index:AdvanceWorldSwitch(opts)
    end

    print("[Shard World Index] Switching to "..tostring(file_id or world_type)..".")
    return index:StartWorldSwitch(opts)
end

function c_returnworld(reason)
    local index = GetConsoleWorldSwitchIndex()
    if index == nil then
        return false
    end

    local state = index:GetState()
    if state == nil or state.active ~= true then
        print("[Shard World Index] No active normal world switch to return from.")
        return false
    end
    if state.kind == "adventure" then
        print("[Shard World Index] Adventure is active; use ShardGameIndex.adventure:ReturnFromShard() instead.")
        return false
    end

    return index:ReturnFromWorldSwitch(reason or "console_return")
end

function c_forestworld()
    return c_switchworld("forest")
end

function c_shipwrecked()
    return c_switchworld("shipwrecked")
end

function c_volcano()
    return c_switchworld("volcano")
end

function c_porkland()
    return c_switchworld("porkland")
end

function c_frograin()
    TheWorld.components.frograin:StartFrogRain()
end
