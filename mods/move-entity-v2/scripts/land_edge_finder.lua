-- 陆地边缘 Tile 查找模块

local LandEdgeFinder = {}

-- Tile 尺寸常量
local TILE_SCALE = 4

-- 全局变量：存储各个 tile 距离海岸线的最近距离
-- 格式：DISTANCE_MAP[tile_x .. "," .. tile_y] = distance
-- 注意：只存储陆地 tile 的距离，不删除
local DISTANCE_MAP = {}

-- 8 个方向的偏移（用于检查陆地边缘）
local DIRECTIONS = {
    {0, 1},   -- 上
    {0, -1},  -- 下
    {-1, 0},  -- 左
    {1, 0},   -- 右
    {-1, 1},  -- 左上
    {1, 1},   -- 右上
    {-1, -1}, -- 左下
    {1, -1}   -- 右下
}

-- 检查 tile 是否是陆地边缘
-- tile_x, tile_y: tile 坐标
-- world: WorldSim 对象
local function IsLandEdgeTile(world, tile_x, tile_y)
    -- 检查当前 tile 是否是陆地
    local tile = world:GetTile(tile_x, tile_y)
    if tile == nil then
        return false
    end
    
    if not TileGroupManager:IsLandTile(tile) then
        return false
    end
    
    -- 检查周围 8 个方向是否有海洋 tile 或 IMPASSABLE tile
    -- 注意：在世界生成时，海洋区域还是 IMPASSABLE tile，会在后续转换为海洋 tile
    for _, dir in ipairs(DIRECTIONS) do
        local neighbor_tile = world:GetTile(tile_x + dir[1], tile_y + dir[2])
        if neighbor_tile then
            -- 检查是否是海洋 tile
            if TileGroupManager:IsOceanTile(neighbor_tile) then
                return true  -- 找到相邻的海洋 tile，说明是陆地边缘
            end
            -- 检查是否是 IMPASSABLE tile（未来的海洋）
            -- 注意：GROUND.IMPASSABLE = 1，在世界生成时，海洋区域还是 IMPASSABLE
            if neighbor_tile == 1 then  -- GROUND.IMPASSABLE = WORLD_TILES.IMPASSABLE = 1
                return true  -- 找到相邻的 IMPASSABLE tile（会在后续转换为海洋），说明是陆地边缘
            end
        end
    end
    
    return false
end

-- 将世界坐标转换为 tile 坐标
-- world_x, world_y: 世界坐标
-- map_width, map_height: 地图尺寸（tile 单位）
local function WorldToTileCoords(world_x, world_y, map_width, map_height)
    local tile_x = math.floor((map_width / 2) + 0.5 + (world_x / TILE_SCALE))
    local tile_y = math.floor((map_height / 2) + 0.5 + (world_y / TILE_SCALE))
    return tile_x, tile_y
end

-- 将 tile 坐标转换为世界坐标（tile 左下角）
-- tile_x, tile_y: tile 坐标
-- map_width, map_height: 地图尺寸（tile 单位）
-- 注意：返回的是 tile 左下角坐标，与 ReserveSpace 返回的格式一致
local function TileToWorldCoords(tile_x, tile_y, map_width, map_height)
    -- tile 左下角坐标（与 ReserveSpace 返回格式一致）
    local world_x = (tile_x - map_width / 2.0) * TILE_SCALE
    local world_y = (tile_y - map_height / 2.0) * TILE_SCALE
    return world_x, world_y
end

-- 计算一个 tile 距离边缘的距离（使用切比雪夫距离）
-- tile_x, tile_y: tile 坐标
-- world: WorldSim 对象
-- 返回: 距离（tile 单位，切比雪夫距离），如果未找到边缘返回 math.huge
local function DistanceToEdge(tile_x, tile_y, world)
    -- 首先检查当前 tile 是否是陆地，如果不是，直接返回 0（距离边缘为 0）
    local tile = world:GetTile(tile_x, tile_y)
    if not tile or not TileGroupManager:IsLandTile(tile) or TileGroupManager:IsOceanTile(tile) then
        return 0  -- 非陆地 tile，距离边缘为 0
    end
    
    -- 获取地图尺寸，用于限制搜索范围（避免搜索超出地图边界）
    local map_width, map_height = world:GetWorldSize()
    if not map_width or not map_height then
        return math.huge  -- 无法获取地图尺寸
    end
    
    -- 计算最大可能的切比雪夫距离（从地图中心到角落的距离）
    local max_chebyshev_dist = math.max(map_width, map_height)
    
    -- 使用切比雪夫距离搜索，找到最近的边缘 tile
    -- 按切比雪夫距离从小到大搜索：从 0 到最大可能距离
    for chebyshev_dist = 0, max_chebyshev_dist do
        -- 遍历所有切比雪夫距离等于 chebyshev_dist 的 tile
        -- 限制搜索范围在合理范围内（避免搜索整个地图）
        local search_range = math.min(chebyshev_dist, math.max(map_width, map_height))
        
        for dx = -search_range, search_range do
            for dy = -search_range, search_range do
                local dist = math.max(math.abs(dx), math.abs(dy))  -- 切比雪夫距离
                
                -- 只检查切比雪夫距离等于当前搜索距离的 tile
                if dist == chebyshev_dist then
                    local tx, ty = tile_x + dx, tile_y + dy
                    
                    -- 确保坐标在地图范围内
                    if tx >= 0 and tx < map_width and ty >= 0 and ty < map_height then
                        if IsLandEdgeTile(world, tx, ty) then
                            return chebyshev_dist  -- 返回切比雪夫距离
                        end
                    end
                end
            end
        end
    end
    
    return math.huge  -- 未找到边缘（理论上不应该发生）
end

-- 预计算所有合法坐标（距离边缘 >= min_distance 的陆地 tile）
-- world: WorldSim 对象
-- min_distance: 最小距离（tile 单位，默认 6）
-- 返回: DISTANCE_MAP 中的 tile 数量
function LandEdgeFinder.PrecomputeValidPositions(world, min_distance)
    min_distance = min_distance or 6
    
    -- 清空之前的距离地图
    DISTANCE_MAP = {}
    
    -- 获取地图尺寸
    local map_width, map_height = world:GetWorldSize()
    if not map_width or not map_height then
        print("[Move Entity V2] ⚠️  无法获取地图尺寸，无法预计算合法坐标")
        return 0
    end
    
    print(string.format(
        "[Move Entity V2] [LandEdgeFinder] 开始预计算合法坐标: 地图尺寸 %d x %d tiles, 最小距离 %d tiles",
        map_width, map_height, min_distance
    ))
    
    local checked_count = 0
    local valid_count = 0
    
    -- 遍历所有 tile
    for y = 0, map_height - 1 do
        for x = 0, map_width - 1 do
            checked_count = checked_count + 1
            
            -- 检查是否是陆地 tile（确保是陆地且不是海洋）
            local tile = world:GetTile(x, y)
            if tile and tile ~= 1 and TileGroupManager:IsLandTile(tile) and not TileGroupManager:IsOceanTile(tile) then
                -- 计算距离边缘的距离（使用切比雪夫距离）
                local dist_to_edge = DistanceToEdge(x, y, world)
                
                -- 存储距离到 DISTANCE_MAP（对所有陆地 tile 都存储，不删除）
                local key = x .. "," .. y
                DISTANCE_MAP[key] = dist_to_edge
                
                -- 如果距离 >= min_distance，计数
                if dist_to_edge >= min_distance then
                    valid_count = valid_count + 1
                end
            end
        end
    end
    
    print(string.format(
        "[Move Entity V2] [LandEdgeFinder] 预计算完成: 检查了 %d 个 tiles, 找到 %d 个合法坐标",
        checked_count, valid_count
    ))
    
    return valid_count
end

-- 查找最近的合法坐标（基于 DISTANCE_MAP）
-- start_tx, start_ty: 起始 tile 坐标
-- world: WorldSim 对象（可选，用于验证 tile 类型）
-- current_exclusion_radius: 当前对象的排斥半径（必须提供，用于基于 DISTANCE_MAP 的距离检查）
-- 返回: new_tx, new_ty (tile 坐标), found (boolean)
function LandEdgeFinder.FindNearestValidPosition(start_tx, start_ty, world, current_exclusion_radius)
    if not current_exclusion_radius then
        print("[Move Entity V2] ⚠️  FindNearestValidPosition: 必须提供 current_exclusion_radius 参数")
        return start_tx, start_ty, false
    end
    
    -- 检查 DISTANCE_MAP 是否为空
    local has_valid_tile = false
    for _ in pairs(DISTANCE_MAP) do
        has_valid_tile = true
        break
    end
    
    if not has_valid_tile then
        print("[Move Entity V2] ⚠️  DISTANCE_MAP 为空，使用原始坐标")
        return start_tx, start_ty, false
    end
    
    local min_dist = math.huge
    local best_tx, best_ty = nil, nil
    local best_dist_in_map = nil
    
    -- 遍历 DISTANCE_MAP 中的所有 tile，找到最近的且满足条件的
    for map_key, dist_in_map in pairs(DISTANCE_MAP) do
        -- 检查距离是否满足条件
        if dist_in_map > current_exclusion_radius then
            -- 解析坐标
            local comma_pos = string.find(map_key, ",")
            if comma_pos then
                local nx = tonumber(string.sub(map_key, 1, comma_pos - 1))
                local ny = tonumber(string.sub(map_key, comma_pos + 1))
                
                if nx and ny then
                    -- 计算到起始位置的切比雪夫距离（Chebyshev distance / L∞ distance）
                    local dx = math.abs(nx - start_tx)
                    local dy = math.abs(ny - start_ty)
                    local dist = math.max(dx, dy)
                    
                    if dist < min_dist then
                        min_dist = dist
                        best_tx = nx
                        best_ty = ny
                        best_dist_in_map = dist_in_map
                    end
                end
            end
        end
    end
    
    if not best_tx or not best_ty then
        print(string.format(
            "[Move Entity V2] ⚠️  未找到满足 DISTANCE_MAP > %d 的合法坐标，使用原始坐标",
            current_exclusion_radius
        ))
        return start_tx, start_ty, false
    end
    
    -- 验证该位置是否是陆地 tile（防止预计算后 tile 被修改）
    if world then
        local tile = world:GetTile(best_tx, best_ty)
        -- 检查是否是有效的陆地 tile：不是 IMPASSABLE (1)，是陆地，不是海洋
        if not tile or tile == 1 or not TileGroupManager:IsLandTile(tile) or TileGroupManager:IsOceanTile(tile) then
            print(string.format(
                "[Move Entity V2] ⚠️  找到的坐标 tile (%d, %d) 不再是陆地 tile（类型: %s），使用原始坐标",
                best_tx, best_ty, tostring(tile)
            ))
            return start_tx, start_ty, false
        end
    end
    
    -- 返回结果
    print(string.format(
        "[Move Entity V2] ✅ 找到最近的合法坐标: tile (%d, %d) -> tile (%d, %d), 移动距离 %d tiles (切比雪夫距离), DISTANCE_MAP=%d",
        start_tx, start_ty, best_tx, best_ty, min_dist, best_dist_in_map
    ))
    return best_tx, best_ty, true
end

-- 清空距离地图（用于世界生成重试）
function LandEdgeFinder.ClearValidPositions()
    DISTANCE_MAP = {}
    print("[Move Entity V2] [LandEdgeFinder] 已清空距离地图")
end

-- 更新 DISTANCE_MAP：将 min_distance 区域内的距离设置为 0（制造空洞），并更新所有 tile 为到海岸线或空洞的最小距离
-- tile_x, tile_y: 已放置建筑的位置（tile 坐标）
-- min_distance: 最小距离（tile 单位，默认 8）
function LandEdgeFinder.RemovePositionsNearby(tile_x, tile_y, min_distance)
    min_distance = min_distance or 8
    
    if not tile_x or not tile_y then
        print("[Move Entity V2] ⚠️  [LandEdgeFinder] RemovePositionsNearby: 无效的坐标参数")
        return
    end
    
    -- 更新所有 tile 的距离为到海岸线或空洞的最小距离
    -- 使用切比雪夫距离（Chebyshev distance / L∞ distance）：max(|dx|, |dy|)
    for map_key, current_distance in pairs(DISTANCE_MAP) do
        -- 解析坐标
        local comma_pos = string.find(map_key, ",")
        if comma_pos then
            local nx = tonumber(string.sub(map_key, 1, comma_pos - 1))
            local ny = tonumber(string.sub(map_key, comma_pos + 1))
            
            if nx and ny then
                -- 计算到空洞中心的切比雪夫距离（Chebyshev distance / L∞ distance）
                local dx = math.abs(nx - tile_x)
                local dy = math.abs(ny - tile_y)
                local dist_to_hole = math.max(dx, dy)
                
                -- 如果距离 <= min_distance，设置为 0（在空洞区域内）
                if dist_to_hole <= min_distance then
                    DISTANCE_MAP[map_key] = 0
                else
                    -- 如果距离 > min_distance，计算到空洞边缘的距离（dist_to_hole - min_distance）
                    local dist_to_hole_edge = dist_to_hole - min_distance
                    
                    -- 更新为到海岸线和空洞的最小距离
                    DISTANCE_MAP[map_key] = math.min(current_distance, dist_to_hole_edge)
                end
            end
        end
    end
end

-- 获取距离地图（返回副本，避免外部修改）
function LandEdgeFinder.GetDistanceMap()
    local result = {}
    for key, distance in pairs(DISTANCE_MAP) do
        result[key] = distance
    end
    return result
end

-- 获取指定 tile 的距离（tile 坐标）
-- 返回: 距离（tile 单位），如果不存在则返回 nil
function LandEdgeFinder.GetDistance(tile_x, tile_y)
    local key = tile_x .. "," .. tile_y
    return DISTANCE_MAP[key]
end

-- 导出坐标转换函数供其他模块使用
LandEdgeFinder.TileToWorldCoords = TileToWorldCoords
LandEdgeFinder.WorldToTileCoords = WorldToTileCoords

-- 导出 DistanceToEdge 函数供其他模块使用
LandEdgeFinder.DistanceToEdge = DistanceToEdge

return LandEdgeFinder

