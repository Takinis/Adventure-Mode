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


local SCANLAYOUT_IGNORE_TAGS = { "locomotor", "NOCLICK", "FX", "DECOR", "placer" }
local SCANLAYOUT_CHUNK_SIZE = 3500
local SCANLAYOUT_SAVE_SHARD = "Master"
local scanlayout_corner = nil
local scanlayout_tile_to_gid = nil

local function GetScanLayoutTileToGid()
    if scanlayout_tile_to_gid == nil then
        scanlayout_tile_to_gid = {}

        local ground_types = require("map/static_layout").GROUND_TYPES
        for gid, tile_id in ipairs(ground_types) do
            if tile_id ~= nil then
                scanlayout_tile_to_gid[tile_id] = gid
            end
        end
    end

    return scanlayout_tile_to_gid
end

local function GetScanLayoutMouseTile()
    if TheInput == nil or TheWorld == nil or TheWorld.Map == nil then
        return nil
    end

    local pos = TheInput:GetWorldPosition()
    if pos == nil then
        return nil
    end

    local tx, tz = TheWorld.Map:GetTileCoordsAtPoint(pos:Get())
    return tx, tz
end

local function GetScanLayoutPlayerTile()
    local player = ConsoleCommandPlayer()
    if player == nil or player.Transform == nil then
        return nil
    end

    local x, y, z = player.Transform:GetWorldPosition()
    local tx, tz = TheWorld.Map:GetTileCoordsAtPoint(x, y, z)
    return tx, tz
end

local function GetScanLayoutBounds(tx1, tz1, tx2, tz2)
    if tx1 == nil or tz1 == nil or tx2 == nil or tz2 == nil then
        return nil
    end

    return {
        min_tx = math.min(tx1, tx2),
        min_tz = math.min(tz1, tz2),
        max_tx = math.max(tx1, tx2),
        max_tz = math.max(tz1, tz2),
    }
end

local function IsScanLayoutEntityScannable(ent, player)
    return ent.prefab ~= nil
        and ent.Transform ~= nil
        and ent ~= player
        and ent.HasAnyTag ~= nil
        and not ent:HasAnyTag(SCANLAYOUT_IGNORE_TAGS)
end

local function CollectScanLayoutEntities(bounds)
    local map = TheWorld.Map
    local player = ConsoleCommandPlayer()
    local seen = {}
    local entities = {}

    for gx = bounds.min_tx, bounds.max_tx do
        for gz = bounds.min_tz, bounds.max_tz do
            local cx, _, cz = map:GetTileCenterPoint(gx, gz)
            for _, ent in ipairs(map:GetEntitiesOnTileAtPoint(cx, 0, cz)) do
                if not seen[ent.GUID] and IsScanLayoutEntityScannable(ent, player) then
                    seen[ent.GUID] = true
                    entities[#entities + 1] = ent
                end
            end
        end
    end

    return entities
end

local function GetScanLayoutObjectProperties(ent)
    local savedrotation = ent.components ~= nil
        and ent.components.savedrotation ~= nil
        and ent.components.savedrotation:OnSave()
        or nil

    return savedrotation ~= nil and { data = { savedrotation = savedrotation } } or {}
end

local function BuildScanLayoutData(bounds)
    local map = TheWorld.Map
    local tilefactor = TILE_SCALE
    local tile_to_gid = GetScanLayoutTileToGid()
    local tiles_w = bounds.max_tx - bounds.min_tx + 1
    local tiles_h = bounds.max_tz - bounds.min_tz + 1
    local tmx_w = tiles_w * tilefactor
    local tmx_h = tiles_h * tilefactor
    local tile_data = {}

    for i = 1, tmx_w * tmx_h do
        tile_data[i] = 0
    end

    for row = 0, tiles_h - 1 do
        for col = 0, tiles_w - 1 do
            local tile_type = map:GetTile(bounds.min_tx + col, bounds.min_tz + row)
            local gid = tile_to_gid[tile_type] or 0
            local tmx_row = row * tilefactor + (tilefactor - 1)
            local tmx_col = col * tilefactor
            tile_data[tmx_row * tmx_w + tmx_col + 1] = gid
        end
    end

    local left_wx, _, left_wz = map:GetTileCenterPoint(bounds.min_tx, bounds.min_tz)
    local right_wx, _, right_wz = map:GetTileCenterPoint(bounds.max_tx, bounds.max_tz)
    local center_x = (left_wx + right_wx) / 2
    local center_z = (left_wz + right_wz) / 2
    local tmx_center_px = tmx_w * 16 / 2
    local tmx_center_py = tmx_h * 16 / 2
    local objects = {}

    for _, ent in ipairs(CollectScanLayoutEntities(bounds)) do
        local wx, _, wz = ent.Transform:GetWorldPosition()
        objects[#objects + 1] = {
            name = "",
            type = ent.prefab,
            shape = "rectangle",
            x = math.floor((wx - center_x) / TILE_SCALE * 64 + tmx_center_px + 0.5),
            y = math.floor((wz - center_z) / TILE_SCALE * 64 + tmx_center_py + 0.5),
            width = 0,
            height = 0,
            visible = true,
            properties = GetScanLayoutObjectProperties(ent),
        }
    end

    return tmx_w, tmx_h, tile_data, objects
end

local function StripScanLayoutReturnPrefix(str)
    return string.gsub(str, "^return%s+", "", 1)
end

local function IndentScanLayoutString(str, indent)
    local lines = {}

    for line in string.gmatch(str.."\n", "(.-)\n") do
        lines[#lines + 1] = indent..line
    end

    return table.concat(lines, "\n")
end

local function DumpScanLayoutTable(value)
    return StripScanLayoutReturnPrefix(DataDumper(value, nil, false))
end

local function AppendScanLayoutTileData(lines, tmx_w, tmx_h, tile_data)
    lines[#lines + 1] = "                data = {"
    for row = 0, tmx_h - 1 do
        local row_values = {}
        for col = 0, tmx_w - 1 do
            row_values[#row_values + 1] = tostring(tile_data[row * tmx_w + col + 1] or 0)
        end
        lines[#lines + 1] = "                    "..table.concat(row_values, ", ")..","
    end
    lines[#lines + 1] = "                },"
end

local function AppendScanLayoutObjects(lines, objects)
    lines[#lines + 1] = "                objects = {"
    for _, obj in ipairs(objects) do
        lines[#lines + 1] = IndentScanLayoutString(DumpScanLayoutTable(obj), "                    ")..","
    end
    lines[#lines + 1] = "                },"
end

local function BuildScanLayoutLua(tmx_w, tmx_h, tile_data, objects)
    local lines = {
        "return {",
        '    version = "1.1",',
        '    luaversion = "5.1",',
        '    orientation = "orthogonal",',
        "    width = "..tostring(tmx_w)..",",
        "    height = "..tostring(tmx_h)..",",
        "    tilewidth = 16,",
        "    tileheight = 16,",
        "    properties = {},",
        "    tilesets = {",
        "        {",
        '            name = "tiles",',
        "            firstgid = 1,",
        "            tilewidth = 64,",
        "            tileheight = 64,",
        "            spacing = 0,",
        "            margin = 0,",
        '            image = "../../../../tools/tiled/dont_starve/tiles.png",',
        "            imagewidth = 512,",
        "            imageheight = 1024,",
        "            properties = {},",
        "            tiles = {},",
        "        },",
        "    },",
        "    layers = {",
        "        {",
        '            type = "tilelayer",',
        '            name = "BG_TILES",',
        "            x = 0,",
        "            y = 0,",
        "            width = "..tostring(tmx_w)..",",
        "            height = "..tostring(tmx_h)..",",
        "            visible = true,",
        "            opacity = 1,",
        "            properties = {},",
        '            encoding = "lua",',
    }

    AppendScanLayoutTileData(lines, tmx_w, tmx_h, tile_data)

    lines[#lines + 1] = "        },"
    lines[#lines + 1] = "        {"
    lines[#lines + 1] = '            type = "objectgroup",'
    lines[#lines + 1] = '            name = "FG_OBJECTS",'
    lines[#lines + 1] = "            visible = true,"
    lines[#lines + 1] = "            opacity = 1,"
    lines[#lines + 1] = "            properties = {},"

    AppendScanLayoutObjects(lines, objects)

    lines[#lines + 1] = "        },"
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "}"

    return table.concat(lines, "\n")
end

local function GetScanLayoutSavePath(filename)
    filename = tostring(filename or "scanlayout_export")
    if string.sub(filename, -4) ~= ".lua" then
        filename = filename..".lua"
    end
    return filename
end

local function GetScanLayoutSaveSlot()
    if ShardGameIndex ~= nil and ShardGameIndex.GetSlot ~= nil then
        local slot = ShardGameIndex:GetSlot()
        if slot ~= nil then
            return slot
        end
    end

    if Settings ~= nil and Settings.save_slot ~= nil then
        return Settings.save_slot
    end

    if SaveGameIndex ~= nil and SaveGameIndex.GetCurrentSaveSlot ~= nil then
        return SaveGameIndex:GetCurrentSaveSlot()
    end
end

local function PrintScanLayoutChunks(lua_src)
    local index = 1
    local count = math.ceil(#lua_src / SCANLAYOUT_CHUNK_SIZE)

    print("[Adventure Mode] Static layout Lua export begin.")
    for chunk = 1, count do
        print(string.format("[Adventure Mode] Static layout chunk %d/%d.", chunk, count))
        print(string.sub(lua_src, index, index + SCANLAYOUT_CHUNK_SIZE - 1))
        index = index + SCANLAYOUT_CHUNK_SIZE
    end
    print("[Adventure Mode] Static layout Lua export end.")
end

local function ExportScanLayout(filename, bounds, print_to_log)
    if bounds == nil then
        print("[Adventure Mode] No static layout bounds.")
        return false
    end

    local tmx_w, tmx_h, tile_data, objects = BuildScanLayoutData(bounds)
    local lua_src = BuildScanLayoutLua(tmx_w, tmx_h, tile_data, objects)
    local save_path = GetScanLayoutSavePath(filename)
    local slot = GetScanLayoutSaveSlot()

    if print_to_log then
        PrintScanLayoutChunks(lua_src)
    end

    if slot ~= nil and TheSim.SetPersistentStringInClusterSlot ~= nil then
        TheSim:SetPersistentStringInClusterSlot(slot, SCANLAYOUT_SAVE_SHARD, save_path, lua_src, false, function()
            print("[Adventure Mode] Static layout exported to Cluster_"..tostring(slot).."/"..SCANLAYOUT_SAVE_SHARD.."/"..save_path)
        end)
    else
        TheSim:SetPersistentString(save_path, lua_src, false, function()
            print("[Adventure Mode] Static layout exported to persistent://"..save_path)
        end)
    end

    return save_path, lua_src
end

function c_scan_mark()
    local tx, tz = GetScanLayoutMouseTile()
    if tx == nil then
        print("[Adventure Mode] Move the mouse over the world before marking a scan layout corner.")
        return false
    end

    scanlayout_corner = { tx = tx, tz = tz }
    print("[Adventure Mode] Static layout first corner: "..tostring(tx)..", "..tostring(tz)..".")
    return true
end

function c_scan_save(filename, print_to_log)
    if scanlayout_corner == nil then
        print("[Adventure Mode] Run c_scan_mark() first.")
        return false
    end

    local tx, tz = GetScanLayoutMouseTile()
    if tx == nil then
        print("[Adventure Mode] Move the mouse over the world before saving the scan layout.")
        return false
    end

    return ExportScanLayout(filename, GetScanLayoutBounds(scanlayout_corner.tx, scanlayout_corner.tz, tx, tz), print_to_log)
end

function c_scan_bounds(filename, tx1, tz1, tx2, tz2, print_to_log)
    return ExportScanLayout(filename, GetScanLayoutBounds(tx1, tz1, tx2, tz2), print_to_log)
end

function c_scan_here(filename, radius, print_to_log)
    local tx, tz = GetScanLayoutPlayerTile()
    if tx == nil then
        print("[Adventure Mode] Console command player is unavailable.")
        return false
    end

    radius = radius or 8
    return ExportScanLayout(filename, GetScanLayoutBounds(tx - radius, tz - radius, tx + radius, tz + radius), print_to_log)
end
