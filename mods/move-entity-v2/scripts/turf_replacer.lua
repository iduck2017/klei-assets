-- 地皮替换模块
-- 功能：将有效坐标的地皮替换为木板地皮（WOODFLOOR）

local TurfReplacer = {}

-- 木板地皮 tile 类型常量
local WOODFLOOR_TILE = 10  -- WORLD_TILES.WOODFLOOR

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
    
    -- 如果已经是木板地皮，跳过
    if current_tile == WOODFLOOR_TILE then
        return false
    end
    
    -- 替换为木板地皮
    world:SetTile(tile_x, tile_y, WOODFLOOR_TILE)
    return true
end

-- 替换有效坐标列表中的所有地皮为木板地皮
-- world: WorldSim 对象
-- valid_positions: 有效坐标列表（包含 tx, ty 字段）
-- 返回: 成功替换的数量
function TurfReplacer.ReplaceValidPositionsWithWoodFloor(world, valid_positions)
    if not world then
        print("[Move Entity V2] [TurfReplacer] ⚠️  无法替换地皮：world 对象为空")
        return 0
    end
    
    if not valid_positions or #valid_positions == 0 then
        print("[Move Entity V2] [TurfReplacer] ⚠️  有效坐标列表为空，无需替换")
        return 0
    end
    
    local replaced_count = 0
    local skipped_count = 0
    
    print(string.format(
        "[Move Entity V2] [TurfReplacer] 开始替换地皮: 共 %d 个有效坐标",
        #valid_positions
    ))
    
    -- 遍历所有有效坐标并替换地皮
    for _, pos in ipairs(valid_positions) do
        if ReplaceSingleTile(world, pos.tx, pos.ty) then
            replaced_count = replaced_count + 1
        else
            skipped_count = skipped_count + 1
        end
    end
    
    print(string.format(
        "[Move Entity V2] [TurfReplacer] 地皮替换完成: 成功替换 %d 个, 跳过 %d 个",
        replaced_count, skipped_count
    ))
    
    return replaced_count
end

-- 替换单个有效坐标的地皮为木板地皮
-- world: WorldSim 对象
-- tile_x, tile_y: tile 坐标
-- 返回: 是否成功替换
function TurfReplacer.ReplaceSingleValidPosition(world, tile_x, tile_y)
    return ReplaceSingleTile(world, tile_x, tile_y)
end

return TurfReplacer

