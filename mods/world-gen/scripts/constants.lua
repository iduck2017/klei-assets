-- 常量定义模块
-- 定义猪王布景相关的实体类型

-- 使用全局变量存储常量（因为modimport不支持返回值）
WorldGenMod_Constants = {
    PIGKING_LAYOUT_ENTITIES = {
        "pigking",
        "insanityrock",
        "sanityrock",
        "pigtorch",
    },
    PIGKING_LAYOUT_RADIUS_ENTITIES = 20, -- 实体搜索半径（单位），需要覆盖insanityrock、sanityrock等较远的实体
    PIGKING_LAYOUT_RADIUS_GROUND = 8, -- 地皮搜索半径（单位），覆盖以猪王为中心的4×4地皮
    TILE_SCALE = 4, -- 一个地块的尺寸
    MAX_SEARCH_RADIUS = 200, -- 最大搜索半径（单位）
}

