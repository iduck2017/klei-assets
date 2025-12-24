-- PigKing 布局处理模块

local LandEdgeFinder = require("land_edge_finder")

local PigkingHandler = {}

-- 判断是否是 DefaultPigking 布局（精确匹配，不区分大小写）
function PigkingHandler.IsPigkingLayout(layout_name)
    if not layout_name then
        return false
    end
    local layout_name_lower = string.lower(layout_name)
    return layout_name_lower == "defaultpigking"
end

-- 统一的 pigking 布局坐标处理函数
-- 输入: rcx, rcy (两个数字) 或 position (表), layout_name, world (WorldSim 对象，可选)
-- 返回: new_rcx, new_rcy, should_modify (boolean) 或 modified_position (表)
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
    
    -- 检查是否是 pigking 布局
    if not PigkingHandler.IsPigkingLayout(layout_name) then
        if is_table_input then
            return rcx, rcy, rcx_or_position
        else
            return rcx, rcy, false
        end
    end
    
    -- 修改坐标：查找最近的陆地边缘 tile
    local old_rcx, old_rcy = rcx, rcy
    local new_rcx, new_rcy
    local found_edge = false
    
    print(string.format(
        "[Move Entity V2] ⚠️  检测到 DefaultPigking 布局: '%s'",
        layout_name
    ))
    
    -- 如果提供了 world 对象，尝试查找陆地边缘
    if world then
        new_rcx, new_rcy, found_edge = LandEdgeFinder.FindNearestLandEdgeTile(old_rcx, old_rcy, world, 20)
        
        if found_edge then
            print(string.format(
                "[Move Entity V2] 🔧 修改 pigking 布局坐标: 原坐标 (%.2f, %.2f) -> 新坐标 (%.2f, %.2f) [移动到陆地边缘]",
                old_rcx, old_rcy, new_rcx, new_rcy
            ))
        else
            -- 未找到陆地边缘，使用原始坐标
            new_rcx = old_rcx
            new_rcy = old_rcy
            print(string.format(
                "[Move Entity V2] ⚠️  未找到陆地边缘，保持原始坐标: (%.2f, %.2f)",
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
    -- 如果找到陆地边缘，返回修改后的坐标；否则返回原始坐标（should_modify = false）
    if is_table_input then
        if found_edge then
            return new_rcx, new_rcy, {new_rcx, new_rcy}
        else
            return rcx, rcy, rcx_or_position
        end
    else
        return new_rcx, new_rcy, found_edge
    end
end

-- 获取 pigking 布局的标记信息（用于日志输出）
function PigkingHandler.GetPigkingMarker(layout_name)
    if PigkingHandler.IsPigkingLayout(layout_name) then
        return "[Move Entity V2]   ⚠️  pigking 布局 - 坐标已偏移 (x+8, y+8)"
    end
    return nil
end

return PigkingHandler

