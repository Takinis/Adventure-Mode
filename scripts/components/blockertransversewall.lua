local TILE_SCALE      = 4                    -- 世界单位/格 / world units per tile
local OBELISK_SPACING = 2                    -- 行内间距（胶囊相切 & 寻路墙相接）/ in-row spacing
local ROW_GAP         = 8 * TILE_SCALE       -- 两道墙间距 = 圆环直径 / gap between the two walls
local EDGE_OVERLAP    = OBELISK_SPACING * 6  -- 压入路缘的深度，封死端口 / bleed into the edge to seal the ends
local EDGE_MARGIN     = 2 * TILE_SCALE       -- 连续不可通行到此即停 / void run that ends the wall
local MAX_HALF_SPAN   = 12 * TILE_SCALE      -- 单侧最大展开 / cap per side along the wall
local REMOVE_RADIUS   = math.sqrt((ROW_GAP * 0.5) ^ 2 + MAX_HALF_SPAN ^ 2) + OBELISK_SPACING * 2

local BlockerTransverseWall = Class(function(self, inst)
    assert(TheWorld.ismastersim, "BlockerTransverseWall should not exist on client")
    assert(inst == TheWorld, "BlockerTransverseWall must be on TheWorld")

    self.inst = inst
    self.task = inst:DoTaskInTime(0, function()
        self.task = nil
        local ok, err = pcall(function()
            self:BuildAllWalls()
        end)
        if not ok then
            print("[blockertransversewall] ERROR: " .. tostring(err))
        end
    end)
end)

local function PrefabForId(id)
    if id:find("InsanityWall", 1, true) then return "insanityrock" end
    if id:find("SanityWall", 1, true) then return "sanityrock" end
    return nil
end

local function Norm(x, z)
    local d = math.sqrt(x * x + z * z)
    if d > 0 then return x / d, z / d end
    return nil
end

local function TravelDir(node, nodes)
    local nb = node.neighbours
    if nb == nil or #nb == 0 then return nil end
    local cx, cz = node.cent[1], node.cent[2]

    local dirs = {}
    for _, nid in ipairs(nb) do
        local n = nodes[nid]
        if n ~= nil and n.cent ~= nil then
            local ux, uz = Norm(n.cent[1] - cx, n.cent[2] - cz)
            if ux ~= nil then
                dirs[#dirs + 1] = { ux = ux, uz = uz, n = n }
            end
        end
    end

    if #dirs == 0 then return nil end
    if #dirs == 1 then return dirs[1].ux, dirs[1].uz end

    local best, bi, bj = math.huge, 1, 2
    for a = 1, #dirs do
        for b = a + 1, #dirs do
            local dot = dirs[a].ux * dirs[b].ux + dirs[a].uz * dirs[b].uz
            if dot < best then best, bi, bj = dot, a, b end
        end
    end
    local A, B = dirs[bi].n, dirs[bj].n
    return Norm(B.cent[1] - A.cent[1], B.cent[2] - A.cent[2])
end

local function PassableSpan(map, cx, cz, dx, dz)
    local edge, void = 0, 0
    local d = OBELISK_SPACING
    while d <= MAX_HALF_SPAN do
        if map:IsPassableAtPoint(cx + dx * d, 0, cz + dz * d) then
            void, edge = 0, d
        else
            void = void + OBELISK_SPACING
            if void >= EDGE_MARGIN then break end
        end
        d = d + OBELISK_SPACING
    end
    return edge
end

local function ProbeTravelDir(map, cx, cz)
    local narrow, na = math.huge, nil
    for deg = 0, 165, 15 do
        local a = math.rad(deg)
        local dx, dz = math.cos(a), math.sin(a)
        local ext = PassableSpan(map, cx, cz, dx, dz) + PassableSpan(map, cx, cz, -dx, -dz)
        if ext < narrow then narrow, na = ext, a end
    end
    if na == nil then return nil end
    local t = na + math.pi * 0.5
    return math.cos(t), math.sin(t)
end

local function SnapToPassable(map, ax, az, tox, toz)
    if map:IsPassableAtPoint(ax, 0, az) then return ax, az end
    local limit = ROW_GAP * 0.5 + EDGE_MARGIN
    local d = OBELISK_SPACING
    while d <= limit do
        local x, z = ax + tox * d, az + toz * d
        if map:IsPassableAtPoint(x, 0, z) then return x, z end
        d = d + OBELISK_SPACING
    end
    return nil
end

local function LocalWallDir(map, ax, az, tx, tz)
    local bnx, bnz = -tz, tx
    local best = PassableSpan(map, ax, az, bnx, bnz) + PassableSpan(map, ax, az, -bnx, -bnz)
    for deg = -60, 60, 5 do
        if deg ~= 0 then
            local a = math.rad(deg)
            local ca, sa = math.cos(a), math.sin(a)
            local nx = -tz * ca - tx * sa        -- 把 perp(T) 旋转 deg / rotate perp(T) by deg
            local nz = -tz * sa + tx * ca
            local ext = PassableSpan(map, ax, az, nx, nz) + PassableSpan(map, ax, az, -nx, -nz)
            if ext < best then best, bnx, bnz = ext, nx, nz end
        end
    end
    return bnx, bnz
end

local function BuildRow(map, prefab, ax, az, nx, nz)
    local dmax =  PassableSpan(map, ax, az,  nx,  nz) + EDGE_OVERLAP
    local dmin = -PassableSpan(map, ax, az, -nx, -nz) - EDGE_OVERLAP
    local d = dmin
    while d <= dmax do
        local o = SpawnPrefab(prefab)
        if o ~= nil then
            o.Transform:SetPosition(ax + nx * d, 0, az + nz * d)
        end
        d = d + OBELISK_SPACING
    end
end

local function BuildBlocker(map, b, nodes)
    local cx, cz = b.cx, b.cz
    local tx, tz = TravelDir(b.node, nodes)
    if tx == nil then
        tx, tz = ProbeTravelDir(map, cx, cz)
    end
    if tx == nil then
        print("[blockertransversewall] no travel axis for node " .. tostring(b.idx) .. "; skipped.")
        return
    end
    local half = ROW_GAP * 0.5
    for _, sgn in ipairs({ 1, -1 }) do
        local ax, az = cx + tx * half * sgn, cz + tz * half * sgn
        ax, az = SnapToPassable(map, ax, az, -tx * sgn, -tz * sgn)   -- 朝中心找路面 / snap toward centre
        if ax ~= nil then
            local nx, nz = LocalWallDir(map, ax, az, tx, tz)         -- 每道墙各自对齐局部横截面 / align each wall locally
            BuildRow(map, b.prefab, ax, az, nx, nz)
        end
    end
end

function BlockerTransverseWall:BuildAllWalls()
    local world = self.inst
    if world == nil or not world.ismastersim then return end
    local map, topo = world.Map, world.topology
    if map == nil or topo == nil or topo.ids == nil or topo.nodes == nil then return end
    local ids, nodes = topo.ids, topo.nodes

    local blockers = {}
    for i, id in ipairs(ids) do
        local prefab = PrefabForId(id)
        local node = nodes[i]
        if prefab ~= nil and node ~= nil and node.cent ~= nil then
            blockers[#blockers + 1] = { idx = i, prefab = prefab, node = node, cx = node.cent[1], cz = node.cent[2] }
        end
    end
    if #blockers == 0 then return end

    -- PASS 1: 清掉每个节点附近旧方尖碑（原版残环 + 上次生成的墙）/ remove existing obelisks first.
    for _, b in ipairs(blockers) do
        for _, e in ipairs(TheSim:FindEntities(b.cx, 0, b.cz, REMOVE_RADIUS, { b.prefab })) do
            e:Remove()
        end
    end

    -- PASS 2: 重建两道横向墙 / rebuild the two transverse walls (after all removals).
    for _, b in ipairs(blockers) do
        BuildBlocker(map, b, nodes)
    end
end

function BlockerTransverseWall:OnRemoveFromEntity()
    if self.task ~= nil then
        self.task:Cancel()
        self.task = nil
    end
end

return BlockerTransverseWall
