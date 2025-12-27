-- 地皮替换模块
-- 功能：将有效坐标的地皮替换为红色大理石路（MOSAIC_RED）

local TurfReplacer = {}

-- 红色大理石路 tile 类型常量
-- 优先使用 WORLD_TILES.MOSAIC_RED，如果不存在则使用 GROUND.MOSAIC_RED（旧版兼容）
local MOSAIC_RED_TILE = nil
local function GetMosaicRedTileID()
    if MOSAIC_RED_TILE == nil then
        if WORLD_TILES and WORLD_TILES.MOSAIC_RED then
            MOSAIC_RED_TILE = WORLD_TILES.MOSAIC_RED
        elseif GROUND and GROUND.MOSAIC_RED then
            MOSAIC_RED_TILE = GROUND.MOSAIC_RED
        else
            -- 如果都不可用，使用硬编码值（GROUND.MOSAIC_RED 通常是 12）
            MOSAIC_RED_TILE = 12
            print("[Move Entity V2] [TurfReplacer] ⚠️  无法获取 MOSAIC_RED tile ID，使用默认值 12")
        end
    end
    return MOSAIC_RED_TILE
end

-- 替换单个 tile 的地皮为木板地皮
-- world: WorldSim 对象
-- tile_x, tile_y: tile 坐标
-- 返回: 是否成功替换
local function ReplaceSingleTile(world, tile_x, tile_y)
    if not world then
        return false
    end
    
    -- 获取当前 tile 类型
    local current_tile = world:GetTile(tile_x, tile_y)
    
    -- 验证 tile 是否有效
    -- 确保不是 IMPASSABLE (1)，是陆地，不是海洋
    if not current_tile or current_tile == 1 then
        return false
    end
    
    if not TileGroupManager:IsLandTile(current_tile) or TileGroupManager:IsOceanTile(current_tile) then
        return false
    end
    
    -- 获取红色大理石路 tile ID
    local mosaic_red_tile = GetMosaicRedTileID()
    
    -- 如果已经是红色大理石路，跳过
    if current_tile == mosaic_red_tile then
        return false
    end
    
    -- 替换为红色大理石路
    world:SetTile(tile_x, tile_y, mosaic_red_tile)
    return true
end

-- 替换所有有效坐标的地皮为红色大理石路（基于 DISTANCE_MAP，只替换值=0的tile）
-- world: WorldSim 对象
-- 返回: 成功替换的数量
function TurfReplacer.ReplaceDistanceMapTilesWithMosaicRed(world)
    if not world then
        print("[Move Entity V2] [TurfReplacer] ⚠️  无法替换地皮：world 对象为空")
        return 0
    end
    
    local LandEdgeFinder = require("land_edge_finder")
    local distance_map = LandEdgeFinder.GetDistanceMap()
    
    if not distance_map then
        print("[Move Entity V2] [TurfReplacer] ⚠️  DISTANCE_MAP 为空，无需替换")
        return 0
    end
    
    local replaced_count = 0
    local skipped_count = 0
    local total_tiles = 0
    
    -- 遍历 DISTANCE_MAP，只替换值=0的tile
    for map_key, dist_value in pairs(distance_map) do
        -- 只替换值=0的tile（值=0表示在空洞内或海岸线，需要替换）
        if dist_value == 0 then
            total_tiles = total_tiles + 1
            
            -- 解析坐标
            local comma_pos = string.find(map_key, ",")
            if comma_pos then
                local tx = tonumber(string.sub(map_key, 1, comma_pos - 1))
                local ty = tonumber(string.sub(map_key, comma_pos + 1))
                
                if tx and ty then
                    if ReplaceSingleTile(world, tx, ty) then
                        replaced_count = replaced_count + 1
                    else
                        skipped_count = skipped_count + 1
                    end
                end
            end
        end
    end
    
    print(string.format(
        "[Move Entity V2] [TurfReplacer] 地皮替换完成: 共检查 %d 个 tile (DISTANCE_MAP = 0), 成功替换 %d 个，跳过 %d 个",
        total_tiles, replaced_count, skipped_count
    ))
    
    return replaced_count
end

-- 替换单个有效坐标的地皮为红色大理石路
-- world: WorldSim 对象
-- tile_x, tile_y: tile 坐标
-- 返回: 是否成功替换
function TurfReplacer.ReplaceSingleValidPosition(world, tile_x, tile_y)
    return ReplaceSingleTile(world, tile_x, tile_y)
end

return TurfReplacer

