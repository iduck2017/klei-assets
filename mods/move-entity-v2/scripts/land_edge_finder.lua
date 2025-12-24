-- 陆地边缘 Tile 查找模块

local LandEdgeFinder = {}

-- Tile 尺寸常量
local TILE_SCALE = 4

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

return LandEdgeFinder

