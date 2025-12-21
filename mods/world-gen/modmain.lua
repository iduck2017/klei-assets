-- ModMain.lua
-- This is the main entry point for your mod

print("World Gen Mod: Loading...")

-- ============================================
-- 功能：在世界生成时将整个猪王布景移动到海边
-- ============================================
-- 在实体生成前修改savedata.ents中的位置，通过hook retrofit_savedata.DoRetrofitting实现

-- 导入hook脚本
modimport("scripts/worldgen_hook")

-- Hook已经在worldgen_hook.lua中完成，这里不需要再次调用

print("World Gen Mod: Mod main file loaded!")

