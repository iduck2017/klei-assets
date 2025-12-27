-- 木牌放置 Hook 模块
-- 功能：在世界生成完成后在 DISTANCE_MAP 中值为 1 的 tile 上放置木牌
-- 使用 PopulateWorld_AddEntity 标准方法
-- Hook GlobalPostPopulate，在世界生成完成后执行

-- 标记是否已经 Hook 过（避免重复安装）
local is_hooked = false

local function InstallSignPlacerHook()
    -- 检查是否已经 Hook 过
    if is_hooked then
        print("[Move Entity V2] [SignPlacerHook] ⚠️  木牌放置 Hook 已安装，跳过重复安装")
        return
    end
    
    -- 先 require network 模块，确保 Graph 类被加载
    local network = require("map/network")
    if not network then
        print("[Move Entity V2] [SignPlacerHook] ⚠️  无法加载 map/network 模块，跳过木牌放置")
        return
    end
    
    -- 验证 Graph 类是否存在
    if not Graph then
        print("[Move Entity V2] [SignPlacerHook] ⚠️  Graph 类不存在，跳过木牌放置")
        return
    end
    
    if not Graph.GlobalPostPopulate then
        print("[Move Entity V2] [SignPlacerHook] ⚠️  Graph.GlobalPostPopulate 不存在，跳过木牌放置")
        return
    end
    
    local SignPlacer = require("sign_placer")
    
    -- Hook Graph:GlobalPostPopulate
    local original_GlobalPostPopulate = Graph.GlobalPostPopulate
    Graph.GlobalPostPopulate = function(self, entities, width, height)
        -- 调试信息：记录所有 GlobalPostPopulate 调用
        print(string.format(
            "[Move Entity V2] [SignPlacerHook] GlobalPostPopulate 被调用: self.id=%s, self.parent=%s, width=%d, height=%d",
            tostring(self.id), tostring(self.parent), width, height
        ))
        
        -- 先调用原始函数
        local result = original_GlobalPostPopulate(self, entities, width, height)
        
        -- 在世界生成完成后放置木牌（只针对根节点）
        -- 注意：此时仍然在世界生成期间，可以使用 PopulateWorld_AddEntity
        if self.parent == nil then
            print("[Move Entity V2] [SignPlacerHook] 检测到根节点，准备放置木牌...")
            
            -- 显式声明全局变量
            local WorldSim = _G.WorldSim
            local world = WorldSim
            if world then
                local map_width, map_height = world:GetWorldSize()
                if map_width and map_height then
                    print(string.format(
                        "[Move Entity V2] [SignPlacerHook] 检测到世界生成完成，开始放置木牌... (地图尺寸: %d x %d)",
                        map_width, map_height
                    ))
                    
                    -- 创建 prefab_list（用于计数，可选）
                    local prefab_list = {}
                    
                    -- 使用标准方法放置木牌
                    local placed = SignPlacer.PlaceSignsAtDistanceOne(entities, map_width, map_height, world, prefab_list)
                    
                    print(string.format(
                        "[Move Entity V2] [SignPlacerHook] 木牌放置完成，共放置 %d 个",
                        placed
                    ))
                else
                    print("[Move Entity V2] [SignPlacerHook] ⚠️  无法获取地图尺寸")
                end
            else
                print("[Move Entity V2] [SignPlacerHook] ⚠️  WorldSim 为空")
            end
        else
            print(string.format(
                "[Move Entity V2] [SignPlacerHook] 跳过非根节点: self.id=%s, self.parent=%s",
                tostring(self.id), tostring(self.parent)
            ))
        end
        
        return result
    end
    
    -- 标记已 Hook
    is_hooked = true
    
    print("[Move Entity V2] [SignPlacerHook] ✅ 木牌放置 Hook 已安装（在世界生成完成后执行，使用标准方法）")
end

return InstallSignPlacerHook

