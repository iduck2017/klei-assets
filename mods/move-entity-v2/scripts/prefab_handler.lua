-- 特殊 Prefab 处理模块（支持多个需要移动的 prefab）

local LandEdgeFinder = require("land_edge_finder")

local PrefabHandler = {}

-- Tile 尺寸常量
local TILE_SCALE = 4

-- 需要应用移动逻辑的 prefab 列表（不区分大小写）
local SPECIAL_PREFABS = {
    "multiplayer_portal",  -- 多人传送门
    "beequeenhive",        -- 蜜蜂女王蜂巢
}

-- 判断是否是需要移动的特殊 prefab（精确匹配，不区分大小写）
function PrefabHandler.ShouldMovePrefab(prefab_name)
    if not prefab_name then
        return false
    end
    local prefab_name_lower = string.lower(prefab_name)
    for _, special_prefab in ipairs(SPECIAL_PREFABS) do
        if prefab_name_lower == string.lower(special_prefab) then
            return true
        end
    end
    return false
end

-- 将 tile 坐标转换为世界坐标
-- tile_x, tile_y: tile 坐标
-- width, height: 地图尺寸（tile 单位）
local function TileToWorldCoords(tile_x, tile_y, width, height)
    local world_x = (tile_x - width/2.0) * TILE_SCALE
    local world_y = (tile_y - height/2.0) * TILE_SCALE
    return world_x, world_y
end

-- 将世界坐标转换为 tile 坐标
-- world_x, world_y: 世界坐标
-- width, height: 地图尺寸（tile 单位）
local function WorldToTileCoords(world_x, world_y, width, height)
    local tile_x = math.floor((width / 2) + 0.5 + (world_x / TILE_SCALE))
    local tile_y = math.floor((height / 2) + 0.5 + (world_y / TILE_SCALE))
    return tile_x, tile_y
end

-- 处理 prefab 坐标
-- prefab: prefab 名称
-- tile_x, tile_y: 原始 tile 坐标
-- width, height: 地图尺寸（tile 单位）
-- world: WorldSim 对象（可选）
-- 返回: new_tile_x, new_tile_y, should_modify (boolean)
function PrefabHandler.ProcessPrefabPosition(prefab, tile_x, tile_y, width, height, world)
    -- 检查是否是需要移动的特殊 prefab
    if not PrefabHandler.ShouldMovePrefab(prefab) then
        return tile_x, tile_y, false
    end
    
    -- 转换为世界坐标
    local world_x, world_y = TileToWorldCoords(tile_x, tile_y, width, height)
    
    -- 查找最近的合法坐标（距离边缘 >= 6 tiles）
    local new_world_x, new_world_y, found_valid = LandEdgeFinder.FindNearestValidPosition(world_x, world_y, world)
    
    if found_valid then
        -- 转换回 tile 坐标
        local new_tile_x, new_tile_y = WorldToTileCoords(new_world_x, new_world_y, width, height)
        
        -- 移除距离该位置 < 8 tiles 的合法坐标（确保主要建筑之间最小距离 >= 8 tiles）
        LandEdgeFinder.RemovePositionsNearby(new_tile_x, new_tile_y, 8)
        
        print(string.format(
            "[Move Entity V2] ⚠️  检测到特殊 Prefab: '%s'",
            prefab
        ))
        print(string.format(
            "[Move Entity V2] 🔧 修改 Prefab '%s' 坐标: tile (%d, %d) -> tile (%d, %d) [移动到合法位置，距离边缘 >= 6 tiles，距离其他主要建筑 >= 8 tiles]",
            prefab, tile_x, tile_y, new_tile_x, new_tile_y
        ))
        
        return new_tile_x, new_tile_y, true
    else
        -- 未找到合法坐标，使用原始坐标
        print(string.format(
            "[Move Entity V2] ⚠️  检测到特殊 Prefab: '%s'，但未找到合法坐标，保持原始坐标: tile (%d, %d)",
            prefab, tile_x, tile_y
        ))
        return tile_x, tile_y, false
    end
end

return PrefabHandler

