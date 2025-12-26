-- 特殊 Prefab 处理模块（支持多个需要移动的 prefab）

local LandEdgeFinder = require("land_edge_finder")

local PrefabHandler = {}

-- Tile 尺寸常量
local TILE_SCALE = 4

-- 需要应用移动逻辑的 prefab 列表（不区分大小写）
local SPECIAL_PREFABS = {
    "multiplayer_portal",  -- 多人传送门
    "beequeenhive",        -- 蜜蜂女王蜂巢
    "critterlab",          -- 宠物领取点（宠物实验室）
    "walrus_camp",         -- 海象巢穴
    "pond",                -- 普通池塘（青蛙池塘）
    "pond_mos",            -- 蚊子池塘
    "pond_cave",           -- 洞穴池塘
}

-- 池塘 prefab 列表（池塘彼此之间不需要互相排斥）
local POND_PREFABS = {
    "pond",
    "pond_mos",
    "pond_cave",
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

-- 判断是否是池塘 prefab（池塘彼此之间不需要互相排斥）
function PrefabHandler.IsPondPrefab(prefab_name)
    if not prefab_name then
        return false
    end
    for _, pond_prefab in ipairs(POND_PREFABS) do
        if prefab_name == pond_prefab then
            return true
        end
    end
    return false
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
    
    -- 直接使用 tile 坐标查找最近的合法坐标（避免不必要的坐标转换）
    local new_tile_x, new_tile_y, found_valid = LandEdgeFinder.FindNearestValidPosition(tile_x, tile_y, world)
    
    if found_valid then
        -- 判断是否是池塘 prefab
        local is_pond = PrefabHandler.IsPondPrefab(prefab)
        
        if is_pond then
            -- 池塘放置后，删除周围 2 tile 距离的 validpos（避免池塘彼此重叠）
            LandEdgeFinder.RemovePositionsNearby(new_tile_x, new_tile_y, 2)
        else
            -- 主要建筑放置后，删除周围 8 tiles 距离的 validpos（确保主要建筑之间最小距离 >= 8 tiles）
            LandEdgeFinder.RemovePositionsNearby(new_tile_x, new_tile_y, 8)
        end
        
        print(string.format(
            "[Move Entity V2] ⚠️  检测到特殊 Prefab: '%s'",
            prefab
        ))
        
        if is_pond then
            print(string.format(
                "[Move Entity V2] 🔧 修改 Prefab '%s' 坐标: tile (%d, %d) -> tile (%d, %d) [移动到合法位置，距离边缘 >= 6 tiles，距离其他主要建筑 >= 8 tiles，池塘彼此之间最小距离 >= 1 tile]",
                prefab, tile_x, tile_y, new_tile_x, new_tile_y
            ))
        else
            print(string.format(
                "[Move Entity V2] 🔧 修改 Prefab '%s' 坐标: tile (%d, %d) -> tile (%d, %d) [移动到合法位置，距离边缘 >= 6 tiles，距离其他主要建筑 >= 8 tiles]",
                prefab, tile_x, tile_y, new_tile_x, new_tile_y
            ))
        end
        
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

