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

local function GetAdventureTestLevels()
    local Levels = require("map/levels")
    local level_ids = {}
    local levels_by_key = {}

    for _, level_entry in ipairs(Levels.GetLevelList(LEVELTYPE.ADVENTURE)) do
        local level_id = level_entry.data
        if type(level_id) == "string" and Levels.GetTypeForLevelID(level_id) == LEVELTYPE.ADVENTURE then
            local key = string.upper(level_id)
            if levels_by_key[key] == nil then
                levels_by_key[key] = level_id
                table.insert(level_ids, level_id)
            end
        end
    end

    table.sort(level_ids)
    return level_ids, levels_by_key
end

local function NormalizeAdventureTestKey(value)
    if value == nil then
        return nil
    end

    local key = tostring(value):match("^%s*(.-)%s*$")
    key = key ~= nil and string.upper(key) or nil
    return key ~= "" and key or nil
end

local function GetAdventureTestLevel(value)
    local key = NormalizeAdventureTestKey(value)
    local _, levels_by_key = GetAdventureTestLevels()
    return key ~= nil and levels_by_key[key] or nil
end

local function PrintAdventureTestUsage()
    local level_ids = GetAdventureTestLevels()
    print("[Adventure Mode] Usage: c_adventure(\"ENDING\")")
    print("[Adventure Mode] Levels: "..table.concat(level_ids, ", ")..".")
end

function c_adventure(level)
    if not ShardGameIndex.adventure:IsMasterShard() then
        print("[Adventure Mode] c_adventure_level must be called on the master shard.")
        return false
    end

    if ShardGameIndex.adventure:IsActive() then
        print("[Adventure Mode] Adventure is already active. Return from it before starting a test level.")
        return false
    end

    local level_id = GetAdventureTestLevel(level)
    if level_id == nil then
        PrintAdventureTestUsage()
        return false
    end

    print("[Adventure Mode] Starting test adventure level "..tostring(level_id)..".")
    return ShardGameIndex.adventure:Start({
        level_sequence = { level_id },
        chapter = string.upper(level_id) == "ENDING" and 2 or 1,
        sequence_id = "test_"..string.lower(level_id),
    })
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
local SCANLAYOUT_HIGHLIGHT = {0.1, 0.1, 1, 0}
local SCANLAYOUT_CHUNK_SIZE = 3500
local SCANLAYOUT_SAVE_SHARD = "Master"
local scanlayout_corner = nil
local scanlayout_tile_to_gid = nil
local scanlayout_state = nil

local SCANLAYOUT_GRID_NEIGHBORS = {
    {dx = -1, dz =  0, dir = "s"},
    {dx =  1, dz =  0, dir = "n"},
    {dx =  0, dz = -1, dir = "e"},
    {dx =  0, dz =  1, dir = "w"},
}
local SCANLAYOUT_GRID_OPPOSITE = { n = "s", s = "n", e = "w", w = "e" }

local function UpdateScanLayoutGridArt(inst, tx, tz)
    local placer = inst.outline_grid:GetDataAtPoint(tx, tz)

    for _, n in ipairs(SCANLAYOUT_GRID_NEIGHBORS) do
        local nplacer = inst.outline_grid:GetDataAtPoint(tx + n.dx, tz + n.dz)
        if nplacer ~= nil then
            if placer ~= nil then
                placer.AnimState:Hide(n.dir)
            else
                nplacer.AnimState:Show(SCANLAYOUT_GRID_OPPOSITE[n.dir])
            end
        end
    end
end

local function PlaceScanLayoutGrid(inst, tx, tz)
    local index = inst.outline_grid:GetIndex(tx, tz)

    if inst.outline_grid:GetDataAtIndex(index) then
        return
    end

    local placer = SpawnPrefab("gridplacer")
    placer.Transform:SetPosition(TheWorld.Map:GetTileCenterPoint(tx, tz))

    inst.outline_grid:SetDataAtIndex(index, placer)
    UpdateScanLayoutGridArt(inst, tx, tz)
end

local function HighlightScanLayoutGrid(inst)
    for index in pairs(inst.outline_grid.grid) do
        inst.outline_grid:GetDataAtIndex(index).AnimState:SetMultColour(0.5, 0.5, 1, 1)
    end
end

local function OnRemoveScanLayoutGrid(inst)
    for index in pairs(inst.outline_grid.grid) do
        inst.outline_grid:GetDataAtIndex(index):Remove()
    end

    inst.outline_grid = nil
end

local function CreateScanLayoutGridOutline()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:SetCanSleep(false)

    inst:AddTag("NOCLICK")
    inst:AddTag("placer")

    inst.persists = false
    inst.outline_grid = DataGrid(TheWorld.Map:GetSize())
    inst.OnRemoveEntity = OnRemoveScanLayoutGrid
    inst.PlaceGrid = PlaceScanLayoutGrid
    inst.Highlight = HighlightScanLayoutGrid

    return inst
end

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

local function UnhighlightScanLayoutEntities(state)
    if state.highlighted == nil then
        return
    end

    for _, ent in pairs(state.highlighted) do
        if ent:IsValid() and ent.AnimState ~= nil then
            ent.AnimState:SetAddColour(0, 0, 0, 0)
        end
    end

    state.highlighted = {}
end

local function HighlightScanLayoutArea(state)
    UnhighlightScanLayoutEntities(state)

    if state.bounds == nil then
        return
    end

    state.highlighted = {}
    for _, ent in ipairs(CollectScanLayoutEntities(state.bounds)) do
        state.highlighted[ent.GUID] = ent
        if ent.AnimState ~= nil then
            ent.AnimState:SetAddColour(unpack(SCANLAYOUT_HIGHLIGHT))
        end
    end
end

local function RebuildScanLayoutOutline(state, min_tx, min_tz, max_tx, max_tz, highlight)
    if state.outline ~= nil then
        state.outline:Remove()
    end

    state.outline = CreateScanLayoutGridOutline()
    state.bounds = {
        min_tx = min_tx,
        min_tz = min_tz,
        max_tx = max_tx,
        max_tz = max_tz,
        tiles_w = max_tx - min_tx + 1,
        tiles_h = max_tz - min_tz + 1,
    }

    for x = min_tx, max_tx do
        for z = min_tz, max_tz do
            state.outline:PlaceGrid(x, z)
        end
    end

    if highlight then
        state.outline:Highlight()
    end
end

local function GetScanLayoutSquareBounds(c1_tx, c1_tz, tx, tz)
    local dx = tx - c1_tx
    local dz = tz - c1_tz
    local side = math.max(math.abs(dx), math.abs(dz))
    local end_tx = c1_tx + side * (dx >= 0 and 1 or -1)
    local end_tz = c1_tz + side * (dz >= 0 and 1 or -1)

    return math.min(c1_tx, end_tx), math.min(c1_tz, end_tz),
        math.max(c1_tx, end_tx), math.max(c1_tz, end_tz)
end

local function StopScanLayoutHandlers(state)
    if state.update_task ~= nil then
        state.update_task:Cancel()
        state.update_task = nil
    end

    if ThePlayer ~= nil and ThePlayer.components.playeractionpicker ~= nil then
        ThePlayer.components.playeractionpicker.rightclickoverride = state.previous_rightclickoverride
    end
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

local function ShowScanLayoutExportPopup()
    local Screen = require "widgets/screen"
    local Widget = require "widgets/widget"
    local Image = require "widgets/image"
    local TextEdit = require "widgets/textedit"
    local Text = require "widgets/text"
    local TEMPLATES = require "widgets/redux/templates"

    local PANEL_W = 480
    local PANEL_H = 230

    local ScanLayoutExportScreen = Class(Screen, function(self)
        Screen._ctor(self, "ScanLayoutExportScreen")

        self.black = self:AddChild(Image("images/global.xml", "square.tex"))
        self.black:SetVRegPoint(ANCHOR_MIDDLE)
        self.black:SetHRegPoint(ANCHOR_MIDDLE)
        self.black:SetVAnchor(ANCHOR_MIDDLE)
        self.black:SetHAnchor(ANCHOR_MIDDLE)
        self.black:SetScaleMode(SCALEMODE_FILLSCREEN)
        self.black:SetTint(0, 0, 0, .75)

        self.proot = self:AddChild(Widget("ROOT"))
        self.proot:SetVAnchor(ANCHOR_MIDDLE)
        self.proot:SetHAnchor(ANCHOR_MIDDLE)
        self.proot:SetPosition(0, 0, 0)
        self.proot:SetScaleMode(SCALEMODE_PROPORTIONAL)

        self.bg = self.proot:AddChild(Image(CRAFTING_ATLAS, "backing.tex"))
        self.bg:SetVRegPoint(ANCHOR_MIDDLE)
        self.bg:SetHRegPoint(ANCHOR_MIDDLE)
        self.bg:ScaleToSize(PANEL_W, PANEL_H)
        self.bg:SetTint(1, 1, 1, 0.95)

        self.border_top = self.proot:AddChild(Image(CRAFTING_ATLAS, "top.tex"))
        self.border_top:SetPosition(0, PANEL_H / 2, 0)
        self.border_top:ScaleToSize(PANEL_W + 6, 10)

        self.border_bottom = self.proot:AddChild(Image(CRAFTING_ATLAS, "bottom.tex"))
        self.border_bottom:SetPosition(0, -PANEL_H / 2, 0)
        self.border_bottom:ScaleToSize(PANEL_W + 6, 10)

        self.border_left = self.proot:AddChild(Image(CRAFTING_ATLAS, "side.tex"))
        self.border_left:SetPosition(-PANEL_W / 2, 0, 0)
        self.border_left:ScaleToSize(6, PANEL_H)

        self.border_right = self.proot:AddChild(Image(CRAFTING_ATLAS, "side.tex"))
        self.border_right:SetPosition(PANEL_W / 2, 0, 0)
        self.border_right:ScaleToSize(6, PANEL_H)

        self.divider = self.proot:AddChild(Image(CRAFTING_ATLAS, "horizontal_bar.tex"))
        self.divider:SetPosition(0, 52, 0)
        self.divider:ScaleToSize(PANEL_W - 20, 3)
        self.divider:SetTint(1, 1, 1, 0.5)

        self.title = self.proot:AddChild(Text(CHATFONT, 38))
        self.title:SetPosition(0, 75, 0)
        self.title:SetColour(215/255, 210/255, 157/255, 1)
        self.title:SetString("Export Selection")

        local slot = GetScanLayoutSaveSlot()
        local path = slot ~= nil and ("Cluster_"..tostring(slot).."/"..SCANLAYOUT_SAVE_SHARD.."/") or "persistent://"
        self.path_label = self.proot:AddChild(Text(CHATFONT, 18))
        self.path_label:SetPosition(0, 38, 0)
        self.path_label:SetColour(0.6, 0.6, 0.5, 1)
        self.path_label:SetString("Saving to: " .. path)

        local edit_width = 380
        local edit_height = 40

        self.edit_bg = self.proot:AddChild(Image("images/global_redux.xml", "textbox3_gold_normal.tex"))
        self.edit_bg:SetPosition(0, -5, 0)
        self.edit_bg:ScaleToSize(edit_width + 20, edit_height)

        self.name_edit = self.proot:AddChild(TextEdit(CHATFONT, 22, "", {.1, .1, .1, 1}))
        self.name_edit:SetPosition(0, -5, 0)
        self.name_edit:SetRegionSize(edit_width - 10, edit_height)
        self.name_edit:SetHAlign(ANCHOR_LEFT)
        self.name_edit:SetFocusedImage(self.edit_bg, "images/global_redux.xml", "textbox3_gold_normal.tex", "textbox3_gold_hover.tex", "textbox3_gold_focus.tex")
        self.name_edit:SetTextLengthLimit(128)
        self.name_edit:SetIdleTextColour(.1, .1, .1, 1)
        self.name_edit:SetEditTextColour(.1, .1, .1, 1)
        self.name_edit:SetForceEdit(true)
        self.name_edit:SetString("")
        self.name_edit.OnTextEntered = function() self:DoExport() end

        local btn_w, btn_h = 170, 45

        self.save_btn = self.proot:AddChild(TEMPLATES.StandardButton(function() self:DoExport() end, "Save", {btn_w, btn_h}))
        self.save_btn:SetPosition(-95, -60, 0)

        self.cancel_btn = self.proot:AddChild(TEMPLATES.StandardButton(function() self:Close() end, "Cancel", {btn_w, btn_h}))
        self.cancel_btn:SetPosition(95, -60, 0)

        self.default_focus = self.name_edit
    end)

    function ScanLayoutExportScreen:OnBecomeActive()
        ScanLayoutExportScreen._base.OnBecomeActive(self)
        self.name_edit:SetFocus()
        self.name_edit:SetEditing(true)
    end

    function ScanLayoutExportScreen:OnRawKey(key, down)
        if ScanLayoutExportScreen._base.OnRawKey(self, key, down) then
            return true
        end
        return false
    end

    function ScanLayoutExportScreen:OnControl(control, down)
        if ScanLayoutExportScreen._base.OnControl(self, control, down) then
            return true
        end
        if control == CONTROL_CANCEL and not down then
            self:Close()
            return true
        end
    end

    function ScanLayoutExportScreen:DoExport()
        local filename = self.name_edit:GetString()
        ExportScanLayout(filename ~= "" and filename or nil, scanlayout_state ~= nil and scanlayout_state.bounds or nil)
        self:Close()
    end

    function ScanLayoutExportScreen:Close()
        TheInput:EnableDebugToggle(true)
        c_scanlayout_clear()
        TheFrontEnd:PopScreen(self)
    end

    TheInput:EnableDebugToggle(false)
    TheFrontEnd:PushScreen(ScanLayoutExportScreen())
end

function c_scanlayout_clear()
    if scanlayout_state == nil then
        return
    end

    StopScanLayoutHandlers(scanlayout_state)
    UnhighlightScanLayoutEntities(scanlayout_state)

    if scanlayout_state.outline ~= nil then
        scanlayout_state.outline:Remove()
    end

    scanlayout_state = nil
end

function c_scanlayout()
    if scanlayout_state ~= nil and not scanlayout_state.done then
        c_scanlayout_clear()
        print("[Adventure Mode] ScanLayout cancelled.")
        return false
    end

    if ThePlayer == nil or ThePlayer.components.playeractionpicker == nil then
        print("[Adventure Mode] ScanLayout needs a local player.")
        return false
    end

    c_scanlayout_clear()

    local state = {
        phase = "pick_first",
        corner1 = nil,
        last_tx = nil,
        last_tz = nil,
        outline = nil,
        bounds = nil,
        highlighted = {},
        done = false,
    }
    scanlayout_state = state

    local map = TheWorld.Map
    state.update_task = TheWorld:DoPeriodicTask(0, function()
        if state.done then
            return
        end

        local tx, tz = GetScanLayoutMouseTile()
        if tx == nil or (tx == state.last_tx and tz == state.last_tz) then
            return
        end
        state.last_tx, state.last_tz = tx, tz

        if state.phase == "pick_first" then
            RebuildScanLayoutOutline(state, tx, tz, tx, tz)
        elseif state.phase == "pick_second" then
            local c1 = state.corner1
            local min_tx, min_tz, max_tx, max_tz = GetScanLayoutSquareBounds(c1.tx, c1.tz, tx, tz)
            UnhighlightScanLayoutEntities(state)
            RebuildScanLayoutOutline(state, min_tx, min_tz, max_tx, max_tz)
            HighlightScanLayoutArea(state)
        end
    end)

    local action = Action({}, 0, true)
    action.id = "SCANLAYOUT"
    action.instant = true
    action.stroverridefn = function()
        return state.phase == "pick_first" and "Start Selection" or "End Selection"
    end
    action.fn = function(act)
        if state.done then
            return true
        end

        local pos = act:GetActionPoint() or TheInput:GetWorldPosition()
        local tx, tz = map:GetTileCoordsAtPoint(pos:Get())

        if state.phase == "pick_first" then
            state.corner1 = {tx = tx, tz = tz}
            state.phase = "pick_second"
        elseif state.phase == "pick_second" then
            local c1 = state.corner1
            local min_tx, min_tz, max_tx, max_tz = GetScanLayoutSquareBounds(c1.tx, c1.tz, tx, tz)

            StopScanLayoutHandlers(state)
            RebuildScanLayoutOutline(state, min_tx, min_tz, max_tx, max_tz, true)
            HighlightScanLayoutArea(state)

            state.done = true
            print(string.format("[Adventure Mode] ScanLayout selected %dx%d tiles.", state.bounds.tiles_w, state.bounds.tiles_h))
            ShowScanLayoutExportPopup()
        end

        return true
    end

    local picker = ThePlayer.components.playeractionpicker
    state.previous_rightclickoverride = picker.rightclickoverride
    picker.rightclickoverride = function(inst, target, position)
        if not state.done then
            return { BufferedAction(inst, nil, action, nil, position) }
        end
        return {}
    end

    return true
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
