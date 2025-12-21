-- WorldGen Hook
-- 这个文件会在mod加载时被导入，用于在实体生成前修改savedata中的位置
-- 通过hook retrofit_savedata.DoRetrofitting来实现

-- 导入所有依赖模块
modimport("scripts/constants")
modimport("scripts/coast_detection")
modimport("scripts/layout_collection")
modimport("scripts/pigking_mover")

-- 确保模块已加载
if not WorldGenMod_PigkingMover then
    error("WorldGenMod_PigkingMover not loaded! Make sure all modules are imported.")
end

local MovePigkingToCoast = WorldGenMod_PigkingMover.MovePigkingToCoast

-- Hook retrofit_savedata.DoRetrofitting来修改savedata.ents
-- 这是标准方式：DoRetrofitting在AddWorldEntities之前调用，且接收world_map作为参数
-- 注意：DoRetrofitting只在PopulateWorld阶段调用，不在世界生成阶段
print("World Gen Mod: Attempting to hook retrofit_savedata.DoRetrofitting...")

-- 延迟require，确保模块已加载
local retrofit_module = nil
local function HookDoRetrofitting()
    if not retrofit_module then
        retrofit_module = require("map/retrofit_savedata")
    end
    
    if retrofit_module and retrofit_module.DoRetrofitting then
        -- 避免重复hook
        if retrofit_module._pigking_coast_hooked then
            return
        end
        
        print("World Gen Mod: Found retrofit_savedata module, hooking DoRetrofitting...")
        
        local original_DoRetrofitting = retrofit_module.DoRetrofitting
        
        retrofit_module.DoRetrofitting = function(savedata, world_map)
            -- 先调用原始函数
            original_DoRetrofitting(savedata, world_map)
            
            print("World Gen Mod: DoRetrofitting called, moving pigking to coast...")
            
            -- 只在PopulateWorld阶段执行（world_map参数存在时）
            -- 在世界生成阶段（worldgen_main.lua），DoRetrofitting不会被调用
            if not world_map then
                print("World Gen Mod: ERROR - world_map parameter is nil")
                return
            end
            
            -- 确认能正确读取tilemap
            print("World Gen Mod: Verifying map access...")
            local test_x, test_z = 0, 0
            local test_tile = world_map:GetTileAtPoint(test_x, 0, test_z)
            if test_tile then
                print("World Gen Mod: Map access verified - tile at (0,0): " .. tostring(test_tile))
            else
                print("World Gen Mod: ERROR - Cannot read tile from map!")
                return
            end
            
            -- 执行移动逻辑（在AddWorldEntities调用之前）
            MovePigkingToCoast(savedata, world_map)
            
            -- 重要：确保savedata.map.tiles被更新（原始函数可能设置了dirty但我们的修改在之后）
            -- 重新从world_map获取最新的tile数据并更新savedata
            savedata.map.tiles = world_map:GetStringEncode()
            savedata.map.nodeidtilemap = world_map:GetNodeIdTileMapStringEncode()
            print("World Gen Mod: Updated savedata.map.tiles and savedata.map.nodeidtilemap after moving pigking")
        end
        
        retrofit_module._pigking_coast_hooked = true
        print("World Gen Mod: Hooked retrofit_savedata.DoRetrofitting successfully!")
    else
        print("World Gen Mod: Error - Could not find retrofit_savedata module or DoRetrofitting function")
    end
end

-- 尝试立即hook（如果模块已加载）
-- 如果失败，在modmain.lua中会再次尝试
HookDoRetrofitting()
