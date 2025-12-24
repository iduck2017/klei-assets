-- 特殊布局处理模块（支持多个需要移动的 layout）

local LandEdgeFinder = require("land_edge_finder")

local PigkingHandler = {}

-- 需要应用移动逻辑的 layout 列表（不区分大小写）
local SPECIAL_LAYOUTS = {
    "DefaultPigking",      -- 猪王
    "DragonflyArena",      -- 龙蝇竞技场
    "MoonbaseOne",         -- 月亮基地
    "Charlie1",            -- 查理舞台 1
    "Charlie2",            -- 查理舞台 2
    "Oasis",               -- 绿洲
    "junk_yard",           -- 垃圾场
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
-- 输入: rcx, rcy (两个数字) 或 position (表), layout_name, world (WorldSim 对象，可选)
-- 返回: new_rcx, new_rcy, should_modify (boolean) 或 modified_position (表)
-- 说明: 如果 layout_name 在 SPECIAL_LAYOUTS 列表中，会尝试移动到距离边缘 >= 6 tiles 的合法位置
function PigkingHandler.ProcessPosition(rcx_or_position, rcy_or_nil, layout_name, world)
    -- 判断输入格式：是 position 表还是两个数字
    local rcx, rcy
    local is_table_input = type(rcx_or_position) == "table"
    
    if is_table_input then
        -- 输入是 position 表
        rcx = rcx_or_position[1]
        rcy = rcx_or_position[2]
    else
        -- 输入是两个数字
        rcx = rcx_or_position
        rcy = rcy_or_nil
    end
    
    -- 检查是否是需要移动的特殊布局
    if not PigkingHandler.ShouldMoveLayout(layout_name) then
        if is_table_input then
            return rcx, rcy, rcx_or_position
        else
            return rcx, rcy, false
        end
    end
    
    -- 修改坐标：查找最近的合法坐标（距离边缘 >= 6 tiles）
    local old_rcx, old_rcy = rcx, rcy
    local new_rcx, new_rcy
    local found_valid = false
    
    print(string.format(
        "[Move Entity V2] ⚠️  检测到特殊布局: '%s'",
        layout_name
    ))
    
    -- 如果提供了 world 对象，尝试查找合法坐标
    if world then
        new_rcx, new_rcy, found_valid = LandEdgeFinder.FindNearestValidPosition(old_rcx, old_rcy, world)
        
        if found_valid then
            print(string.format(
                "[Move Entity V2] 🔧 修改布局 '%s' 坐标: 原坐标 (%.2f, %.2f) -> 新坐标 (%.2f, %.2f) [移动到合法位置，距离边缘 >= 6 tiles]",
                layout_name, old_rcx, old_rcy, new_rcx, new_rcy
            ))
        else
            -- 未找到合法坐标，使用原始坐标
            new_rcx = old_rcx
            new_rcy = old_rcy
            print(string.format(
                "[Move Entity V2] ⚠️  未找到合法坐标，保持原始坐标: (%.2f, %.2f)",
                old_rcx, old_rcy
            ))
        end
    else
        -- 没有 world 对象，使用原始坐标
        new_rcx = old_rcx
        new_rcy = old_rcy
        print(string.format(
            "[Move Entity V2] ⚠️  无 world 对象，保持原始坐标: (%.2f, %.2f)",
            old_rcx, old_rcy
        ))
    end
    
    -- 根据输入格式返回相应格式
    -- 如果找到合法坐标，返回修改后的坐标；否则返回原始坐标（should_modify = false）
    if is_table_input then
        if found_valid then
            return new_rcx, new_rcy, {new_rcx, new_rcy}
        else
            return rcx, rcy, rcx_or_position
        end
    else
        return new_rcx, new_rcy, found_valid
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

