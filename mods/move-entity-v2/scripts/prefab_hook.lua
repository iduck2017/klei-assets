-- Prefab Hook 模块：劫持 PopulateWorld_AddEntity 以修改特殊 prefab 的坐标

local PrefabHandler = require("prefab_handler")

local function InstallPrefabHook()
    -- 加载 graphnode 模块以确保 PopulateWorld_AddEntity 已定义
    local graphnode = require("map/graphnode")
    
    -- 获取原始函数（PopulateWorld_AddEntity 是全局函数）
    local original_PopulateWorld_AddEntity = _G.PopulateWorld_AddEntity
    
    if not original_PopulateWorld_AddEntity then
        print("[Move Entity V2] ⚠️  无法找到 PopulateWorld_AddEntity 函数，Prefab Hook 未安装")
        return
    end
    
    -- Hook PopulateWorld_AddEntity
    _G.PopulateWorld_AddEntity = function(prefab, tile_x, tile_y, tile_value, entitiesOut, width, height, prefab_list, prefab_data, rand_offset)
        -- 检查是否是特殊 prefab
        if PrefabHandler.ShouldMovePrefab(prefab) then
            -- 处理坐标
            local new_tile_x, new_tile_y, should_modify = PrefabHandler.ProcessPrefabPosition(
                prefab, tile_x, tile_y, width, height, WorldSim
            )
            
            if should_modify then
                -- 使用新坐标调用原始函数
                return original_PopulateWorld_AddEntity(
                    prefab, new_tile_x, new_tile_y, tile_value, entitiesOut, width, height, prefab_list, prefab_data, rand_offset
                )
            end
        end
        
        -- 普通 prefab 或未找到合法坐标，使用原始坐标
        return original_PopulateWorld_AddEntity(
            prefab, tile_x, tile_y, tile_value, entitiesOut, width, height, prefab_list, prefab_data, rand_offset
        )
    end
    
    print("[Move Entity V2] ✅ Prefab Hook 已安装")
end

return InstallPrefabHook

