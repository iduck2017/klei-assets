local PigkingHandler = require("pigking_handler")

-- 复制 MinBoundingBox 函数（因为它是 object_layout.lua 中的 local 函数）
local function MinBoundingBox(items)
    local extents = {xmin=1000000, ymin=1000000, xmax=-1000000, ymax=-1000000}
    for k, pos in pairs(items) do
        if pos[1] < extents.xmin then
            extents.xmin = pos[1]
        end
        if pos[1] > extents.xmax then
            extents.xmax = pos[1]
        end
        if pos[2] < extents.ymin then
            extents.ymin = pos[2]
        end
        if pos[2] > extents.ymax then
            extents.ymax = pos[2]
        end
    end
    return extents
end

local function InstallLayoutHook()
    local obj_layout = require("map/object_layout")
    if not obj_layout then
        return
    end
    
    local original_Convert = obj_layout.Convert
    local original_ReserveAndPlaceLayout = obj_layout.ReserveAndPlaceLayout
    
    if not original_Convert or not original_ReserveAndPlaceLayout then
        return
    end
    
    obj_layout.ReserveAndPlaceLayout = function(node_id, layout, prefabs, add_entity, position, world)
        local layout_name = layout.name or layout.layout_file or "Unknown"
        local original_world = world or WorldSim
        local wrapped_world = original_world
        local modified_position = position
        
        if not position then
            -- 自动寻找位置模式：所有布局都通过 Convert Hook 处理，这里不会被执行
            -- 保留此分支是为了兼容性（防止直接调用 ReserveAndPlaceLayout 的情况）
            wrapped_world = original_world
        end
        
        return original_ReserveAndPlaceLayout(node_id, layout, prefabs, add_entity, modified_position, wrapped_world)
    end
    
    obj_layout.Convert = function(node_id, item, addEntity)
        local layout = obj_layout.LayoutForDefinition(item)
        if not layout then
            return original_Convert(node_id, item, addEntity)
        end
        
        local layout_name = layout.name or layout.layout_file or item
        local prefabs = obj_layout.ConvertLayoutToEntitylist(layout)
        
        -- 计算边界框和 size（与 ReserveAndPlaceLayout 内部逻辑一致）
        local item_positions = {}
        for i, val in ipairs(prefabs) do
            table.insert(item_positions, {val.x, val.y})
        end
        
        local extents = MinBoundingBox(item_positions)
        
        -- 计算 size
        local e_width = (extents.xmax - extents.xmin) / 2.0
        local e_height = (extents.ymax - extents.ymin) / 2.0
        local size = e_width
        if size < e_height then
            size = e_height
        end
        size = layout.scale * size
        
        -- 如果 layout.ground 存在，使用 ground_size（与 ReserveAndPlaceLayout 第 349-405 行逻辑一致）
        if layout.ground ~= nil then
            local ground_size = #layout.ground
            size = ground_size / 2.0
        end
        
        -- 设置默认值
        layout.start_mask = layout.start_mask or 0
        layout.fill_mask = layout.fill_mask or 0
        layout.layout_position = layout.layout_position or 0
        
        -- 调用 ReserveSpace 获取原始坐标
        -- 注意：传入 nil 作为 tiles，这样 ReserveSpace 不会放置地皮，只会保留空间
        -- 然后我们设置 position，让代码走 position ~= nil 分支，地皮会在新位置放置一次
        local world = WorldSim
        local old_rcx, old_rcy = world:ReserveSpace(node_id, size, layout.start_mask, layout.fill_mask, layout.layout_position, nil)
        
        if old_rcx then
            -- 处理 pigking 布局坐标修改（只在这里调用一次）
            local new_rcx, new_rcy, should_modify = PigkingHandler.ProcessPosition(old_rcx, old_rcy, layout_name)
            
            -- 无论是否需要修改，都设置 position，避免进入 ReserveSpace Wrapper 分支
            -- 这样可以确保 ProcessPosition 只调用一次
            if not should_modify then
                new_rcx = old_rcx
                new_rcy = old_rcy
            end
            
            -- 记录布局名称和位置
            print(string.format(
                "[Move Entity V2] 布局 '%s' -> 位置 (%.2f, %.2f)",
                layout_name, new_rcx, new_rcy
            ))
            
            -- 创建 position（已在 Convert Hook 中处理过，确保只调用一次 ProcessPosition）
            local position = {new_rcx, new_rcy}
            
            return obj_layout.ReserveAndPlaceLayout(node_id, layout, prefabs, addEntity, position, world)
        else
            -- ReserveSpace 失败，使用原始流程
            return obj_layout.ReserveAndPlaceLayout(node_id, layout, prefabs, addEntity, nil, world)
        end
    end
end

return InstallLayoutHook

