-- 常量定义模块
-- 定义需要移动到海边的布局配置

-- 使用全局变量存储常量（因为modimport不支持返回值）
WorldGenMod_Constants = {
    -- 布局配置表：每个布局类型包含中心实体、相关实体、搜索半径等
    LAYOUT_CONFIGS = {
        pigking = {
            center_entity = "pigking",  -- 中心实体（用于定位布局）
            related_entities = {        -- 相关实体（需要一起移动）
                "pigking",
                "insanityrock",
                "sanityrock",
                "pigtorch",
            },
            radius_entities = 20,      -- 实体搜索半径（单位）
            radius_ground = 8,          -- 地皮搜索半径（单位），覆盖4×4地皮
            move_ground = true,         -- 是否移动地皮
        },
        beequeen = {
            center_entity = "beequeenhive",  -- 中心实体（世界生成时使用的是beequeenhive，不是beequeenhivegrown）
            related_entities = {              -- 相关实体（只移动中心实体本身）
                "beequeenhive",
            },
            radius_entities = 0,       -- 实体搜索半径（单位），0表示只移动中心实体本身
            radius_ground = 0,         -- 地皮搜索半径（单位），0表示不收集地皮
            move_ground = false,       -- 不移动地皮，只移动实体
        },
    },
    TILE_SCALE = 4, -- 一个地块的尺寸
    MAX_SEARCH_RADIUS = 200, -- 最大搜索半径（单位）
}

