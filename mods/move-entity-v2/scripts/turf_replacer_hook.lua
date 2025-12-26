-- 地皮替换 Hook 模块
-- 功能：在世界生成完成后替换所有有效坐标的地皮为红色大理石路
-- 这是一个独立的模块，不与其他逻辑耦合
-- Hook GlobalPostPopulate，在世界生成完成后执行

local function InstallTurfReplacerHook()
    -- 先 require network 模块，确保 Graph 类被加载
    -- 这是精确的方案：在安装 Hook 之前确保依赖已加载
    local network = require("map/network")
    if not network then
        print("[Move Entity V2] [TurfReplacerHook] ⚠️  无法加载 map/network 模块，跳过地皮替换")
        return
    end
    
    -- 验证 Graph 类是否存在
    if not Graph then
        print("[Move Entity V2] [TurfReplacerHook] ⚠️  Graph 类不存在，跳过地皮替换")
        return
    end
    
    if not Graph.GlobalPostPopulate then
        print("[Move Entity V2] [TurfReplacerHook] ⚠️  Graph.GlobalPostPopulate 不存在，跳过地皮替换")
        return
    end
    
    local LandEdgeFinder = require("land_edge_finder")
    local TurfReplacer = require("turf_replacer")
    
    -- Hook Graph:GlobalPostPopulate
    local original_GlobalPostPopulate = Graph.GlobalPostPopulate
    Graph.GlobalPostPopulate = function(self, entities, width, height)
        -- 先调用原始函数
        local result = original_GlobalPostPopulate(self, entities, width, height)
        
        -- 在世界生成完成后替换地皮（只针对根节点）
        -- 注意：不需要 turf_replaced 检查，因为：
        -- 1. GlobalPostPopulate 在每次成功的生成尝试中只被调用一次
        -- 2. ReplaceSingleTile 中已有检查：如果地皮已经是 MOSAIC_RED，会跳过
        if self.parent == nil then
            local valid_count = LandEdgeFinder.GetValidPositionsCount()
            if valid_count > 0 then
                local world = WorldSim
                if world then
                    print("[Move Entity V2] [TurfReplacerHook] 检测到世界生成完成，开始替换地皮...")
                    local valid_positions = LandEdgeFinder.GetValidPositions()
                    if valid_positions and #valid_positions > 0 then
                        TurfReplacer.ReplaceValidPositionsWithMosaicRed(world, valid_positions)
                        print("[Move Entity V2] [TurfReplacerHook] 地皮替换完成")
                    end
                end
            end
        end
        
        return result
    end
    
    print("[Move Entity V2] [TurfReplacerHook] ✅ 地皮替换 Hook 已安装（在世界生成完成后执行）")
end

return InstallTurfReplacerHook

