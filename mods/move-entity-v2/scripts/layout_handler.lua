-- 特殊布局处理模块（支持多个需要移动的 layout）

local LandEdgeFinder = require("land_edge_finder")

local PigkingHandler = {}

-- 需要应用移动逻辑的 layout 列表（不区分大小写）
local SPECIAL_LAYOUTS = {
    "DefaultPigking",           -- 猪王 8
    "DragonflyArena",          -- 龙蝇竞技场 12
    "MoonbaseOne",             -- 月亮基地 8
    "Charlie1",                -- 查理舞台-1 8
    "Charlie2",                -- 查理舞台-2 4
    "Oasis",                   -- 绿洲 12
    "junk_yard",               -- 垃圾场 8
    "CaveEntrance",            -- 洞穴入口 4
    "WormholeGrass",           -- 虫洞（基础类型）4
    "MooseNest",               -- 麋鹿鹅生成器 4
    "ResurrectionStone",       -- 复活石（标准）4
    "Balatro",                 -- 小丑牌游戏机 4
}

-- Layout 排斥半径映射表（layout 名称 -> 排斥半径）
local LAYOUT_EXCLUSION_RADIUS = {
    ["defaultpigking"] = 5,
    ["dragonflyarena"] = 9,
    ["moonbaseone"] = 5,
    ["charlie1"] = 5,
    ["charlie2"] = 2,
    ["oasis"] = 7,
    ["junk_yard"] = 5,
    ["caveentrance"] = 2,
    ["wormholegrass"] = 2,
    ["moosenest"] = 2,
    ["resurrectionstone"] = 2,
    ["balatro"] = 2,
}

-- 判断是否是需要移动的特殊布局（精确匹配，不区分大小写）
function PigkingHandler.ShouldMoveLayout(layout_name)
    if not layout_name then
        return false
    end
    local layout_name_lower = string.lower(layout_name)
    for _, special_layout in ipairs(SPECIAL_LAYOUTS) do
        if layout_name_lower == string.lower(special_layout) then
            return true
        end
    end
    return false
end

-- 判断是否是 DefaultPigking 布局（向后兼容，精确匹配，不区分大小写）
function PigkingHandler.IsPigkingLayout(layout_name)
    if not layout_name then
        return false
    end
    local layout_name_lower = string.lower(layout_name)
    return layout_name_lower == "defaultpigking"
end

-- 统一的特殊布局坐标处理函数（支持多个 layout）
-- 输入: tx, ty (两个数字，tile 坐标) 或 position (表，tile 坐标), layout_name, world (WorldSim 对象，可选)
-- 返回: new_tx, new_ty (tile 坐标), should_modify (boolean) 或 modified_position (表)
-- 说明: 如果 layout_name 在 SPECIAL_LAYOUTS 列表中，会尝试移动到距离边缘 >= 6 tiles 的合法位置
function PigkingHandler.ProcessPosition(tx_or_position, ty_or_nil, layout_name, world)
    -- 判断输入格式：是 position 表还是两个数字
    local tx, ty
    local is_table_input = type(tx_or_position) == "table"
    
    if is_table_input then
        -- 输入是 position 表
        tx = tx_or_position[1]
        ty = tx_or_position[2]
    else
        -- 输入是两个数字
        tx = tx_or_position
        ty = ty_or_nil
    end
    
    -- 检查是否是需要移动的特殊布局
    if not PigkingHandler.ShouldMoveLayout(layout_name) then
        if is_table_input then
            return tx, ty, tx_or_position
        else
            return tx, ty, false
        end
    end
    
    -- 修改坐标：查找最近的合法坐标（距离边缘 >= 6 tiles）
    -- 注意：tx, ty 是 tile 坐标（从 ReserveSpace 返回）
    local old_tx, old_ty = tx, ty
    local new_tx, new_ty
    local found_valid = false
    
    print(string.format(
        "[Move Entity V2] ⚠️  检测到特殊布局: '%s'",
        layout_name
    ))
    
    -- 如果提供了 world 对象，尝试查找合法坐标
    if world then
        -- 获取地图尺寸
        local map_width, map_height = world:GetWorldSize()
        if not map_width or not map_height then
            print("[Move Entity V2] ⚠️  无法获取地图尺寸，保持原始坐标")
            new_tx = old_tx
            new_ty = old_ty
        else
            -- 根据 layout 名称获取排斥半径
            local layout_name_lower = string.lower(layout_name)
            local exclusion_radius = LAYOUT_EXCLUSION_RADIUS[layout_name_lower] or 8  -- 默认 8
            
            -- 直接使用 tile 坐标查找最近的合法坐标（避免不必要的坐标转换）
            -- 传入 exclusion_radius 参数，基于 DISTANCE_MAP 进行距离检查
            local found
            new_tx, new_ty, found = LandEdgeFinder.FindNearestValidPosition(old_tx, old_ty, world, exclusion_radius)
        
            if found then
                found_valid = true
                
                -- 移除距离该位置 < exclusion_radius tiles 的合法坐标，并更新 DISTANCE_MAP
                LandEdgeFinder.RemovePositionsNearby(new_tx, new_ty, exclusion_radius)
                
            print(string.format(
                    "[Move Entity V2] 🔧 修改布局 '%s' 坐标: tile (%d, %d) -> tile (%d, %d) [移动到合法位置，距离边缘 >= 6 tiles，排斥半径 %d tiles]",
                    layout_name, old_tx, old_ty, new_tx, new_ty, exclusion_radius
            ))
        else
            -- 未找到合法坐标，使用原始坐标
                new_tx = old_tx
                new_ty = old_ty
            print(string.format(
                    "[Move Entity V2] ⚠️  未找到合法坐标，保持原始坐标: tile (%d, %d)",
                    old_tx, old_ty
            ))
            end
        end
    else
        -- 没有 world 对象，使用原始坐标
        new_tx = old_tx
        new_ty = old_ty
        print(string.format(
            "[Move Entity V2] ⚠️  无 world 对象，保持原始坐标: tile (%d, %d)",
            old_tx, old_ty
        ))
    end
    
    -- 根据输入格式返回相应格式
    -- 注意：返回的是 tile 坐标（与 ReserveSpace 返回格式一致）
    -- 如果找到合法坐标，返回修改后的坐标；否则返回原始坐标（should_modify = false）
    if is_table_input then
        if found_valid then
            return new_tx, new_ty, {new_tx, new_ty}
        else
            return tx, ty, tx_or_position
        end
    else
        return new_tx, new_ty, found_valid
    end
end

-- 获取布局的标记信息（用于日志输出，向后兼容）
function PigkingHandler.GetPigkingMarker(layout_name)
    if PigkingHandler.ShouldMoveLayout(layout_name) then
        return string.format("[Move Entity V2]   ⚠️  布局 '%s' - 坐标已移动到合法位置", layout_name)
    end
    return nil
end

return PigkingHandler

