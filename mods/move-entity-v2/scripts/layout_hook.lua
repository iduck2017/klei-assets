local PigkingHandler = require("pigking_handler")

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
        local captured_rcx = nil
        local captured_rcy = nil
        local position_type = nil
        
        local original_world = world or WorldSim
        local wrapped_world = original_world
        local modified_position = position
        
        if position then
            -- 指定位置：处理 pigking 布局坐标修改
            captured_rcx, captured_rcy, modified_position = PigkingHandler.ProcessManualPosition(position, layout_name)
            position_type = "manual"
            
            print(string.format(
                "[Move Entity V2] Layout '%s' - 关键点1: 保留空间确定 (指定位置) - rcx=%.2f, rcy=%.2f (左下角坐标)",
                layout_name, captured_rcx, captured_rcy
            ))
        else
            -- 自动寻找位置：包装 world 对象以拦截 ReserveSpace
            wrapped_world = setmetatable({}, {__index = original_world})
            wrapped_world.ReserveSpace = function(self, ...)
                local rcx, rcy = original_world.ReserveSpace(original_world, ...)
                if rcx then
                    captured_rcx = rcx
                    captured_rcy = rcy
                    position_type = "auto"
                    
                    -- 处理 pigking 布局坐标修改
                    local new_rcx, new_rcy, should_return = PigkingHandler.ProcessAutoPosition(rcx, rcy, layout_name)
                    if should_return then
                        captured_rcx = new_rcx
                        captured_rcy = new_rcy
                        return new_rcx, new_rcy
                    end
                    
                    print(string.format(
                        "[Move Entity V2] Layout '%s' - 关键点1: 保留空间确定 (自动寻找位置) - rcx=%.2f, rcy=%.2f (左下角坐标)",
                        layout_name, rcx, rcy
                    ))
                end
                return rcx, rcy
            end
        end
        
        local result = original_ReserveAndPlaceLayout(node_id, layout, prefabs, add_entity, modified_position, wrapped_world)
        
        if captured_rcx then
            print(string.format("[Move Entity V2] ========================================"))
            print(string.format("[Move Entity V2] Layout 放置信息:"))
            print(string.format("[Move Entity V2]   布局名称: %s", layout_name))
            print(string.format("[Move Entity V2]   节点ID: %s", tostring(node_id)))
            print(string.format("[Move Entity V2]   位置类型: %s", position_type or "unknown"))
            print(string.format("[Move Entity V2]   保留区域左下角坐标: rcx=%.2f, rcy=%.2f", captured_rcx, captured_rcy))
            
            -- 获取 pigking 标记信息
            local pigking_marker = PigkingHandler.GetPigkingMarker(layout_name)
            if pigking_marker then
                print(pigking_marker)
            end
            
            print(string.format("[Move Entity V2]   Prefab数量: %d", #prefabs))
            if layout.scale then
                print(string.format("[Move Entity V2]   缩放因子: %.2f", layout.scale))
            end
            print(string.format("[Move Entity V2] ========================================"))
        end
        
        return result
    end
    
    obj_layout.Convert = function(node_id, item, addEntity)
        local layout = obj_layout.LayoutForDefinition(item)
        if not layout then
            return original_Convert(node_id, item, addEntity)
        end
        
        local layout_name = layout.name or layout.layout_file or item
        local prefabs = obj_layout.ConvertLayoutToEntitylist(layout)
        
        print(string.format(
            "[Move Entity V2] Convert: 布局 '%s' 在节点 '%s' 开始处理",
            layout_name, tostring(node_id)
        ))
        
        return obj_layout.ReserveAndPlaceLayout(node_id, layout, prefabs, addEntity)
    end
end

return InstallLayoutHook

