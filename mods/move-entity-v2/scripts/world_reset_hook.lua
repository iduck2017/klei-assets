-- 世界重置 Hook 模块
-- 功能：Hook forest_map.Generate 来检测世界生成重试，清空 VALID_POSITIONS 并重置相关标记
-- 这是一个独立的模块，用于处理世界生成重试时的状态重置
-- 方案：Hook forest_map.Generate，在每次调用开始时清空 VALID_POSITIONS
-- 因为每次世界生成尝试（包括重试）都会调用 forest_map.Generate

local function InstallWorldResetHook()
    local LandEdgeFinder = require("land_edge_finder")
    
    -- Hook forest_map.Generate
    -- 每次世界生成尝试（包括重试）都会调用这个函数
    local forest_map = require("map/forest_map")
    if not forest_map then
        print("[Move Entity V2] [WorldResetHook] ⚠️  forest_map 不存在，无法安装 Hook")
        return
    end
    
    local original_Generate = forest_map.Generate
    if not original_Generate then
        print("[Move Entity V2] [WorldResetHook] ⚠️  forest_map.Generate 不存在，无法安装 Hook")
        return
    end
    
    -- Hook Generate，在每次调用开始时清空 VALID_POSITIONS
    forest_map.Generate = function(prefab, map_width, map_height, tasks, level, level_type)
        -- 每次 Generate 被调用时（包括重试），清空 VALID_POSITIONS
        -- 这样确保使用新的世界数据重新预计算
        LandEdgeFinder.ClearValidPositions()
        print("[Move Entity V2] 🔄 检测到世界生成（或重试），已清空 VALID_POSITIONS")
        
        -- 调用原始函数
        return original_Generate(prefab, map_width, map_height, tasks, level, level_type)
    end
    
    print("[Move Entity V2] [WorldResetHook] ✅ 已 Hook forest_map.Generate，将在每次世界生成时清空 VALID_POSITIONS")
end

return InstallWorldResetHook

