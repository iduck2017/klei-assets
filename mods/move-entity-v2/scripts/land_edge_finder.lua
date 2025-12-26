-- 陆地边缘 Tile 查找模块

local LandEdgeFinder = {}

-- Tile 尺寸常量
local TILE_SCALE = 4

-- 全局变量：存储所有合法坐标（距离边缘 >= min_distance 的陆地 tile）
local VALID_POSITIONS = {}

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

-- 计算一个 tile 距离边缘的距离
-- tile_x, tile_y: tile 坐标
-- world: WorldSim 对象
-- max_radius: 最大搜索半径（tile 单位，默认 20）
-- min_required: 最小需要的距离（如果距离小于此值，可以提前返回，用于优化）
-- 返回: 距离（tile 单位），如果未找到边缘返回 math.huge
local function DistanceToEdge(tile_x, tile_y, world, max_radius, min_required)
    max_radius = max_radius or 20
    min_required = min_required or 0
    
    -- 首先检查当前 tile 是否是陆地，如果不是，直接返回 0（距离边缘为 0）
    local tile = world:GetTile(tile_x, tile_y)
    if not tile or not TileGroupManager:IsLandTile(tile) or TileGroupManager:IsOceanTile(tile) then
        return 0  -- 非陆地 tile，距离边缘为 0
    end
    
    -- 使用螺旋搜索，找到最近的边缘 tile
    for radius = 0, max_radius do
        -- 优化：如果已经搜索到 min_required 距离，且还没找到边缘，说明距离 >= min_required
        -- 但如果 min_required > 0，我们需要继续搜索确认距离是否真的 >= min_required
        if min_required > 0 and radius >= min_required then
            -- 如果搜索到 min_required 距离还没找到边缘，说明距离 >= min_required
            -- 但为了准确，我们需要继续搜索到 max_radius 或找到边缘
        end
        
        for dx = -radius, radius do
            for dy = -radius, radius do
                -- 只检查当前层的边界 tile（避免重复检查内层）
                if math.abs(dx) == radius or math.abs(dy) == radius then
                    local tx, ty = tile_x + dx, tile_y + dy
                    if IsLandEdgeTile(world, tx, ty) then
                        return radius  -- 返回距离（tile 单位）
                    end
                end
            end
        end
        
        -- 优化：如果 min_required > 0 且 radius >= min_required，且还没找到边缘
        -- 说明距离 >= min_required，可以提前返回（但为了准确，我们继续搜索）
    end
    
    return math.huge  -- 未找到边缘
end

-- 预计算所有合法坐标（距离边缘 >= min_distance 的陆地 tile）
-- world: WorldSim 对象
-- min_distance: 最小距离（tile 单位，默认 6）
-- 返回: 合法坐标数量
function LandEdgeFinder.PrecomputeValidPositions(world, min_distance)
    min_distance = min_distance or 6
    
    -- 清空之前的合法坐标
    VALID_POSITIONS = {}
    
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
                -- 检查距离边缘是否 >= min_distance
                -- 使用足够大的搜索半径（20）以确保找到最近的边缘
                local dist_to_edge = DistanceToEdge(x, y, world, 20, 0)
                
                if dist_to_edge >= min_distance then
                    -- 转换为世界坐标并存储
                    local world_x, world_y = TileToWorldCoords(x, y, map_width, map_height)
                    table.insert(VALID_POSITIONS, {
                        tx = x,
                        ty = y,
                        world_x = world_x,
                        world_y = world_y
                    })
                    valid_count = valid_count + 1
                end
            end
        end
    end
    
    print(string.format(
        "[Move Entity V2] [LandEdgeFinder] 预计算完成: 检查了 %d 个 tiles, 找到 %d 个合法坐标",
        checked_count, valid_count
    ))
    
    -- 绘制有效坐标的可视化地图（20x20 网格）
    LandEdgeFinder.DrawValidPositionsMap(map_width, map_height, world)
    
    return valid_count
end

-- 绘制有效坐标的可视化地图（20x20 网格）
-- map_width, map_height: 地图尺寸（tile 单位）
-- world: WorldSim 对象（可选，用于识别月岛）
function LandEdgeFinder.DrawValidPositionsMap(map_width, map_height, world)
    local grid_size = 20
    local grid = {}
    local grid_has_valid = {}  -- 标记每个网格区域是否有有效坐标
    
    -- 初始化网格（全部为空）
    for y = 1, grid_size do
        grid[y] = {}
        grid_has_valid[y] = {}
        for x = 1, grid_size do
            grid[y][x] = "口"  -- 使用汉字"口"作为填充单位
            grid_has_valid[y][x] = false
        end
    end
    
    -- 将有效坐标映射到网格中
    for _, pos in ipairs(VALID_POSITIONS) do
        -- 将 tile 坐标映射到 0-19 的网格坐标
        local grid_x = math.floor((pos.tx / map_width) * grid_size) + 1
        local grid_y = math.floor((pos.ty / map_height) * grid_size) + 1
        
        -- 确保在范围内
        if grid_x >= 1 and grid_x <= grid_size and grid_y >= 1 and grid_y <= grid_size then
            grid_has_valid[grid_y][grid_x] = true
        end
    end
    
    -- 根据统计结果设置网格字符
    for y = 1, grid_size do
        for x = 1, grid_size do
            if grid_has_valid[y][x] then
                -- 有有效位置，使用"■"
                grid[y][x] = "区"
            else
                -- 无有效位置，保持"口"
                grid[y][x] = "口"
            end
        end
    end
    
    -- 输出网格（从上到下，y 从大到小，对应地图的北到南）
    print("[Move Entity V2] [LandEdgeFinder] ========== 有效坐标分布图（20x20 网格）==========")
    print("[Move Entity V2] [LandEdgeFinder] 图例: ■=有有效位置, 口=无有效位置")
    print("[Move Entity V2] [LandEdgeFinder] 地图尺寸: " .. map_width .. " x " .. map_height .. " tiles")
    print("[Move Entity V2] [LandEdgeFinder] " .. string.rep("─", grid_size + 2))
    
    -- 输出列号（可选，帮助定位）
    local header = "│ "
    for x = 1, grid_size do
        header = header .. (x % 10)
    end
    header = header .. " │"
    print("[Move Entity V2] [LandEdgeFinder] " .. header)
    print("[Move Entity V2] [LandEdgeFinder] " .. string.rep("─", grid_size + 2))
    
    -- 输出网格内容（从上到下）
    for y = grid_size, 1, -1 do
        local line = "│"
        for x = 1, grid_size do
            line = line .. grid[y][x]
        end
        line = line .. "│ " .. string.format("%2d", y)  -- 显示行号
        print("[Move Entity V2] [LandEdgeFinder] " .. line)
    end
    
    print("[Move Entity V2] [LandEdgeFinder] " .. string.rep("─", grid_size + 2))
    print("[Move Entity V2] [LandEdgeFinder] ================================================")
end

-- 查找最近的合法坐标（基于 tile 坐标）
-- start_tx, start_ty: 起始 tile 坐标
-- world: WorldSim 对象（可选，用于验证 tile 类型）
-- 返回: new_tx, new_ty (tile 坐标), found (boolean)
function LandEdgeFinder.FindNearestValidPosition(start_tx, start_ty, world)
    if #VALID_POSITIONS == 0 then
        print("[Move Entity V2] ⚠️  合法坐标集合为空，使用原始坐标")
        return start_tx, start_ty, false
    end
    
    -- 使用循环查找最近的合法坐标，并验证其有效性
    local max_attempts = 10  -- 最多尝试 10 次，避免无限循环
    local attempt = 0
    
    while attempt < max_attempts do
        attempt = attempt + 1
        
        local min_dist_sq = math.huge
        local best_pos = nil
        
        -- 遍历所有合法坐标，找到最近的
        for _, pos in ipairs(VALID_POSITIONS) do
            local dx = pos.tx - start_tx
            local dy = pos.ty - start_ty
            local dist_sq = dx * dx + dy * dy
            
            if dist_sq < min_dist_sq then
                min_dist_sq = dist_sq
                best_pos = pos
            end
        end
        
        if not best_pos then
            print("[Move Entity V2] ⚠️  未找到合法坐标，使用原始坐标")
            return start_tx, start_ty, false
        end
        
        -- 再次验证该位置是否是陆地 tile（防止预计算后 tile 被修改）
        if world then
            local tile = world:GetTile(best_pos.tx, best_pos.ty)
            -- 检查是否是有效的陆地 tile：不是 IMPASSABLE (1)，是陆地，不是海洋
            if not tile or tile == 1 or not TileGroupManager:IsLandTile(tile) or TileGroupManager:IsOceanTile(tile) then
                print(string.format(
                    "[Move Entity V2] ⚠️  预计算的合法坐标 tile (%d, %d) 不再是陆地 tile（类型: %s），跳过并继续查找",
                    best_pos.tx, best_pos.ty, tostring(tile)
                ))
                -- 从合法坐标集合中移除这个无效坐标
                for i, pos in ipairs(VALID_POSITIONS) do
                    if pos.tx == best_pos.tx and pos.ty == best_pos.ty then
                        table.remove(VALID_POSITIONS, i)
                        break
                    end
                end
                -- 继续下一次循环，查找下一个最近的合法坐标
                best_pos = nil
            else
                -- 验证通过，返回结果
                -- 计算新坐标距离边缘的实际距离
                local actual_dist_to_edge = DistanceToEdge(best_pos.tx, best_pos.ty, world, 20, 0)
                local dist = math.sqrt(min_dist_sq)  -- 从原位置到新位置的移动距离
                local dist_to_edge_str = (actual_dist_to_edge == math.huge) and ">20" or string.format("%.2f", actual_dist_to_edge)
                print(string.format(
                    "[Move Entity V2] ✅ 找到最近的合法坐标: tile (%d, %d) -> tile (%d, %d), 移动距离 %.2f tiles, 距离边缘 %s tiles",
                    start_tx, start_ty, best_pos.tx, best_pos.ty, dist, dist_to_edge_str
                ))
                return best_pos.tx, best_pos.ty, true
            end
        else
            -- 没有 world 对象，无法验证，直接返回（理论上不应该发生）
            local dist = math.sqrt(min_dist_sq)
            print(string.format(
                "[Move Entity V2] ✅ 找到最近的合法坐标: tile (%d, %d) -> tile (%d, %d), 移动距离 %.2f tiles（未验证）",
                start_tx, start_ty, best_pos.tx, best_pos.ty, dist
            ))
            return best_pos.tx, best_pos.ty, true
        end
    end
    
    -- 尝试次数过多，返回失败
    print("[Move Entity V2] ⚠️  尝试查找合法坐标次数过多，使用原始坐标")
    return start_tx, start_ty, false
end

-- 清空合法坐标集合（用于世界生成重试）
function LandEdgeFinder.ClearValidPositions()
    VALID_POSITIONS = {}
    print("[Move Entity V2] [LandEdgeFinder] 已清空合法坐标集合")
end

-- 移除距离指定位置 < min_distance 的合法坐标（用于主要建筑之间最小距离限制）
-- tile_x, tile_y: 已放置建筑的位置（tile 坐标）
-- min_distance: 最小距离（tile 单位，默认 8）
-- 返回: 移除的坐标数量
function LandEdgeFinder.RemovePositionsNearby(tile_x, tile_y, min_distance)
    min_distance = min_distance or 8
    
    if not tile_x or not tile_y then
        print("[Move Entity V2] ⚠️  [LandEdgeFinder] RemovePositionsNearby: 无效的坐标参数")
        return 0
    end
    
    local removed_count = 0
    
    -- 从后往前遍历，避免删除时索引问题
    for i = #VALID_POSITIONS, 1, -1 do
        local pos = VALID_POSITIONS[i]
        local dx = pos.tx - tile_x
        local dy = pos.ty - tile_y
        local dist = math.sqrt(dx * dx + dy * dy)
        
        if dist < min_distance then
            table.remove(VALID_POSITIONS, i)
            removed_count = removed_count + 1
        end
    end
    
    if removed_count > 0 then
        print(string.format(
            "[Move Entity V2] [LandEdgeFinder] 移除了 %d 个距离 tile (%d, %d) < %d tiles 的合法坐标（剩余 %d 个合法坐标）",
            removed_count, tile_x, tile_y, min_distance, #VALID_POSITIONS
        ))
    end
    
    return removed_count
end

-- 获取合法坐标集合（返回副本，避免外部修改）
function LandEdgeFinder.GetValidPositions()
    local result = {}
    for _, pos in ipairs(VALID_POSITIONS) do
        table.insert(result, {
            tx = pos.tx,
            ty = pos.ty,
            world_x = pos.world_x,
            world_y = pos.world_y
        })
    end
    return result
end

-- 获取合法坐标数量
function LandEdgeFinder.GetValidPositionsCount()
    return #VALID_POSITIONS
end

-- 导出坐标转换函数供其他模块使用
LandEdgeFinder.TileToWorldCoords = TileToWorldCoords
LandEdgeFinder.WorldToTileCoords = WorldToTileCoords

return LandEdgeFinder

