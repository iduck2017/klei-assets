-- 木牌放置模块
-- 功能：在 DISTANCE_MAP 中值为 1 的 tile 上放置木牌
-- 使用 PopulateWorld_AddEntity 标准方法

local SignPlacer = {}

-- 显式声明全局变量
local TileGroupManager = _G.TileGroupManager
local TILE_SCALE = 4

-- 确保全局变量已定义
if not TileGroupManager then
    error("[Move Entity V2] [SignPlacer] TileGroupManager 未定义")
end

-- 在指定位置放置木牌（使用标准方法）
-- entities: 实体输出表（entitiesOut）
-- width, height: 地图尺寸（tile 单位）
-- world: WorldSim 对象
-- prefab_list: prefab 计数表（可选，如果为 nil 则创建空表）
-- 返回: 成功放置的数量
function SignPlacer.PlaceSignsAtDistanceOne(entities, width, height, world, prefab_list)
    if not entities then
        print("[Move Entity V2] [SignPlacer] ⚠️  无法放置木牌：entities 为空")
        return 0
    end
    
    if not world then
        print("[Move Entity V2] [SignPlacer] ⚠️  无法放置木牌：world 为空")
        return 0
    end
    
    -- 确保 PopulateWorld_AddEntity 已加载
    if not _G.PopulateWorld_AddEntity then
        require("map/graphnode")
    end
    
    if not _G.PopulateWorld_AddEntity then
        print("[Move Entity V2] [SignPlacer] ⚠️  无法找到 PopulateWorld_AddEntity 函数")
        return 0
    end
    
    local LandEdgeFinder = require("land_edge_finder")
    local distance_map = LandEdgeFinder.GetDistanceMap()
    
    if not distance_map then
        print("[Move Entity V2] [SignPlacer] ⚠️  DISTANCE_MAP 为空，无需放置木牌")
        return 0
    end
    
    -- 如果没有提供 prefab_list，创建空表
    if not prefab_list then
        prefab_list = {}
    end
    
    local placed_count = 0
    local skipped_count = 0
    local total_tiles = 0
    local checked_tiles = 0
    
    print(string.format(
        "[Move Entity V2] [SignPlacer] 开始检查 DISTANCE_MAP，查找值为 1 的 tile..."
    ))
    
    -- 遍历 DISTANCE_MAP，只在值=1的tile上放置木牌
    for map_key, dist_value in pairs(distance_map) do
        checked_tiles = checked_tiles + 1
        
        -- 只在值=1的tile上放置木牌
        if dist_value == 1 then
            total_tiles = total_tiles + 1
            
            -- 解析坐标
            local comma_pos = string.find(map_key, ",")
            if comma_pos then
                local tile_x = tonumber(string.sub(map_key, 1, comma_pos - 1))
                local tile_y = tonumber(string.sub(map_key, comma_pos + 1))
                
                if tile_x and tile_y then
                    -- 获取 tile 类型
                    local tile = world:GetTile(tile_x, tile_y)
                    if not tile or tile == 1 then
                        skipped_count = skipped_count + 1
                    elseif not TileGroupManager:IsLandTile(tile) or TileGroupManager:IsOceanTile(tile) then
                        skipped_count = skipped_count + 1
                    else
                        -- 使用标准方法 PopulateWorld_AddEntity 放置木牌
                        -- 参数：prefab, tile_x, tile_y, tile_value, entitiesOut, width, height, prefab_list, prefab_data, rand_offset
                        -- 注意：使用 "homesign" 作为木牌 prefab
                        _G.PopulateWorld_AddEntity(
                            "homesign",        -- prefab
                            tile_x,           -- tile_x
                            tile_y,           -- tile_y
                            tile,             -- tile_value
                            entities,         -- entitiesOut
                            width,            -- width
                            height,           -- height
                            prefab_list,      -- prefab_list
                            nil,              -- prefab_data (可选)
                            false             -- rand_offset (false = 不添加随机偏移，保持位置精确)
                        )
                        
                        placed_count = placed_count + 1
                    end
                else
                    print(string.format(
                        "[Move Entity V2] [SignPlacer] ⚠️  无法解析坐标: %s", map_key
                    ))
                    skipped_count = skipped_count + 1
                end
            else
                print(string.format(
                    "[Move Entity V2] [SignPlacer] ⚠️  坐标格式错误: %s", map_key
                ))
                skipped_count = skipped_count + 1
            end
        end
    end
    
    print(string.format(
        "[Move Entity V2] [SignPlacer] 木牌放置完成: 共检查 %d 个 tile, 找到 %d 个 DISTANCE_MAP = 1 的 tile, 成功放置 %d 个，跳过 %d 个",
        checked_tiles, total_tiles, placed_count, skipped_count
    ))
    
    return placed_count
end

return SignPlacer

