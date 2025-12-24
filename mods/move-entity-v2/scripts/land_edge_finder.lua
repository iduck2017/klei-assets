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

-- 查找最近的陆地边缘 tile
-- world_x, world_y: 起始世界坐标
-- world: WorldSim 对象
-- max_radius: 最大搜索半径（tile 单位，默认 20）
-- 返回: new_world_x, new_world_y, found (boolean)
function LandEdgeFinder.FindNearestLandEdgeTile(world_x, world_y, world, max_radius)
    max_radius = max_radius or 20
    
    print(string.format(
        "[Move Entity V2] [LandEdgeFinder] 开始查找陆地边缘: 起始世界坐标 (%.2f, %.2f), 最大半径 %d tiles",
        world_x, world_y, max_radius
    ))
    
    -- 获取地图尺寸
    local map_width, map_height = world:GetWorldSize()
    if not map_width or not map_height then
        print("[Move Entity V2] ⚠️  无法获取地图尺寸，使用默认值")
        -- 如果无法获取，使用默认值（通常 DST 地图是 350x350 tiles）
        map_width = 350
        map_height = 350
    end
    
    print(string.format(
        "[Move Entity V2] [LandEdgeFinder] 地图尺寸: %d x %d tiles",
        map_width, map_height
    ))
    
    -- 将世界坐标转换为 tile 坐标
    local start_tx, start_ty = WorldToTileCoords(world_x, world_y, map_width, map_height)
    
    print(string.format(
        "[Move Entity V2] [LandEdgeFinder] 起始 tile 坐标: (%d, %d)",
        start_tx, start_ty
    ))
    
    -- 边界检查
    if start_tx < 0 or start_tx >= map_width or start_ty < 0 or start_ty >= map_height then
        print(string.format(
            "[Move Entity V2] ⚠️  起始坐标超出地图范围: tile (%d, %d), 地图尺寸 (%d, %d)",
            start_tx, start_ty, map_width, map_height
        ))
        return world_x, world_y, false
    end
    
    -- 调试：检查起始位置的 tile 类型
    local start_tile = world:GetTile(start_tx, start_ty)
    local is_start_land = start_tile and TileGroupManager:IsLandTile(start_tile) or false
    local is_start_ocean = start_tile and TileGroupManager:IsOceanTile(start_tile) or false
    print(string.format(
        "[Move Entity V2] [LandEdgeFinder] 起始位置 tile 类型: %s (陆地: %s, 海洋: %s)",
        tostring(start_tile), tostring(is_start_land), tostring(is_start_ocean)
    ))
    
    -- 螺旋搜索：从内到外，逐层搜索
    local checked_count = 0
    local land_count = 0
    local ocean_count = 0
    
    for radius = 0, max_radius do
        for dx = -radius, radius do
            for dy = -radius, radius do
                -- 只检查当前层的边界 tile（避免重复检查内层）
                if math.abs(dx) == radius or math.abs(dy) == radius then
                    local tx, ty = start_tx + dx, start_ty + dy
                    
                    -- 边界检查
                    if tx >= 0 and tx < map_width and ty >= 0 and ty < map_height then
                        checked_count = checked_count + 1
                        local tile = world:GetTile(tx, ty)
                        
                        if tile then
                            if TileGroupManager:IsLandTile(tile) then
                                land_count = land_count + 1
                            elseif TileGroupManager:IsOceanTile(tile) then
                                ocean_count = ocean_count + 1
                            end
                        end
                        
                        -- 检查是否是陆地边缘
                        if IsLandEdgeTile(world, tx, ty) then
                            -- 转换为世界坐标（tile 左下角，与 ReserveSpace 返回格式一致）
                            local new_world_x, new_world_y = TileToWorldCoords(tx, ty, map_width, map_height)
                            
                            -- 确保坐标是 tile 对齐的（tile 左下角）
                            -- tile 左下角格式: n * TILE_SCALE
                            -- 这确保了 delta 是 TILE_SCALE 的倍数（4 的倍数）
                            new_world_x = math.floor(new_world_x / TILE_SCALE) * TILE_SCALE
                            new_world_y = math.floor(new_world_y / TILE_SCALE) * TILE_SCALE
                            
                            print(string.format(
                                "[Move Entity V2] ✅ 找到陆地边缘 tile: tile (%d, %d) -> 世界坐标 (%.2f, %.2f) [左下角] (搜索了 %d 个 tiles, 找到 %d 个陆地, %d 个海洋)",
                                tx, ty, new_world_x, new_world_y, checked_count, land_count, ocean_count
                            ))
                            
                            return new_world_x, new_world_y, true
                        end
                    end
                end
            end
        end
    end
    
    -- 未找到陆地边缘
    print(string.format(
        "[Move Entity V2] ⚠️  在半径 %d tiles 内未找到陆地边缘，使用原始坐标 (搜索了 %d 个 tiles, 找到 %d 个陆地, %d 个海洋)",
        max_radius, checked_count, land_count, ocean_count
    ))
    return world_x, world_y, false
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
            if tile and TileGroupManager:IsLandTile(tile) and not TileGroupManager:IsOceanTile(tile) then
                -- 检查距离边缘是否 >= min_distance
                -- 优化：如果搜索到 min_distance 距离还没找到边缘，说明距离 >= min_distance
                -- 但为了准确，我们搜索到 min_distance + 5 以确保找到最近的边缘
                local dist_to_edge = DistanceToEdge(x, y, world, min_distance + 5, min_distance)
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
    
    return valid_count
end

-- 查找最近的合法坐标
-- world_x, world_y: 起始世界坐标
-- map_width, map_height: 地图尺寸（tile 单位，可选，如果不提供则从 world 获取）
-- 返回: new_world_x, new_world_y, found (boolean)
function LandEdgeFinder.FindNearestValidPosition(world_x, world_y, world, map_width, map_height)
    if #VALID_POSITIONS == 0 then
        print("[Move Entity V2] ⚠️  合法坐标集合为空，使用原始坐标")
        return world_x, world_y, false
    end
    
    -- 获取地图尺寸
    if not map_width or not map_height then
        if world then
            map_width, map_height = world:GetWorldSize()
        end
        if not map_width or not map_height then
            print("[Move Entity V2] ⚠️  无法获取地图尺寸，使用原始坐标")
            return world_x, world_y, false
        end
    end
    
    -- 将起始坐标转换为 tile 坐标
    local start_tx, start_ty = WorldToTileCoords(world_x, world_y, map_width, map_height)
    
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
            return world_x, world_y, false
        end
        
        -- 再次验证该位置是否是陆地 tile（防止预计算后 tile 被修改）
        if world then
            local tile = world:GetTile(best_pos.tx, best_pos.ty)
            if not tile or not TileGroupManager:IsLandTile(tile) or TileGroupManager:IsOceanTile(tile) then
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
                local dist = math.sqrt(min_dist_sq)
                print(string.format(
                    "[Move Entity V2] ✅ 找到最近的合法坐标: tile (%d, %d) -> 世界坐标 (%.2f, %.2f), 距离 %.2f tiles",
                    best_pos.tx, best_pos.ty, best_pos.world_x, best_pos.world_y, dist
                ))
                return best_pos.world_x, best_pos.world_y, true
            end
        else
            -- 没有 world 对象，无法验证，直接返回（理论上不应该发生）
            local dist = math.sqrt(min_dist_sq)
            print(string.format(
                "[Move Entity V2] ✅ 找到最近的合法坐标: tile (%d, %d) -> 世界坐标 (%.2f, %.2f), 距离 %.2f tiles (未验证)",
                best_pos.tx, best_pos.ty, best_pos.world_x, best_pos.world_y, dist
            ))
            return best_pos.world_x, best_pos.world_y, true
        end
    end
    
    -- 尝试次数过多，返回失败
    print("[Move Entity V2] ⚠️  尝试查找合法坐标次数过多，使用原始坐标")
    return world_x, world_y, false
end

-- 清空合法坐标集合（用于世界生成重试）
function LandEdgeFinder.ClearValidPositions()
    VALID_POSITIONS = {}
    print("[Move Entity V2] [LandEdgeFinder] 已清空合法坐标集合")
end

return LandEdgeFinder

