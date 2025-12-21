-- ModMain.lua
-- This is the main entry point for your mod

print("My Mod: Loading...")

-- ============================================
-- DEMO: 将所有玩家的生命上限改为500
-- ============================================
-- 参考: dstmod.com 和 Klei官方文档
-- 
-- 问题分析：
-- 1. AddPlayerPostInit 在 master_postinit 之前调用，此时health组件可能还未添加
-- 2. health组件在 master_postinit 中被添加并立即调用 SetMaxHealth(TUNING.WILSON_HEALTH)
-- 3. 因此需要在 master_postinit 之后修改，使用监听事件的方式

-- 使用 AddComponentPostInit 修改health组件
AddComponentPostInit("health", function(self)
    -- 检查是否是玩家
    if self.inst and self.inst:HasTag("player") then
        -- 保存原始的SetMaxHealth方法
        local original_SetMaxHealth = self.SetMaxHealth
        
        -- 重写SetMaxHealth方法，确保玩家始终使用500作为最大生命值
        self.SetMaxHealth = function(health_component, amount)
            -- 如果是玩家，强制设置为500
            if health_component.inst and health_component.inst:HasTag("player") then
                amount = 500
            end
            -- 调用原始方法
            return original_SetMaxHealth(health_component, amount)
        end
        
        -- 延迟设置，确保在master_postinit之后执行
        self.inst:DoTaskInTime(0.1, function()
            if self.inst and self.inst.components.health then
                -- 只在服务器端执行
                if TheWorld ~= nil and TheWorld.ismastersim then
                    local current_health_percent = self.inst.components.health:GetPercent()
                    self.inst.components.health:SetMaxHealth(500)
                    self.inst.components.health:SetPercent(current_health_percent)
                    print("My Mod: Player max health set to 500!")
                end
            end
        end)
    end
end)

-- ============================================
-- 其他示例代码（已注释）
-- ============================================

-- Prefab files will be automatically loaded from the prefabs/ folder
-- Component files will be automatically loaded from the components/ folder
-- StateGraph files will be automatically loaded from the stategraphs/ folder

-- Example: Add prefabs (uncomment and add your prefab names)
-- PrefabFiles = {
--     "my_prefab",
--     "my_item",
-- }

-- Example: Add assets (uncomment and add your asset paths)
-- Assets = {
--     Asset("IMAGE", "images/my_image.tex"),
--     Asset("ATLAS", "images/my_image.xml"),
-- }

-- Example: Import additional scripts
-- modimport("scripts/myscript")

-- Example: Modify existing components
-- AddComponentPostInit("health", function(self)
--     -- Modify health component here
--     -- self:DoSomething()
-- end)

-- Example: Modify specific character (e.g., only Wilson)
-- AddPrefabPostInit("wilson", function(inst)
--     if inst.components.health then
--         inst.components.health:SetMaxHealth(500)
--     end
-- end)

-- Example: Add world generation modifications
-- AddSimPostInit(function()
--     -- World generation modifications
--     -- TheWorld:DoSomething()
-- end)

print("My Mod: Mod main file loaded!")

