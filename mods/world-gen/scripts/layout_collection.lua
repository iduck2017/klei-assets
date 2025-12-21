-- 布景收集模块
-- 用于从savedata中收集布局的所有实体
-- 基于位置范围收集实体，不依赖布局定义

-- 确保常量已加载
if not WorldGenMod_Constants then
    error("WorldGenMod_Constants not loaded! Make sure constants.lua is imported first.")
end

local TILE_SCALE = WorldGenMod_Constants.TILE_SCALE
local LAYOUT_CONFIGS = WorldGenMod_Constants.LAYOUT_CONFIGS

-- 函数：计算两点之间的距离
local function Distance(x1, z1, x2, z2)
    local dx = x2 - x1
    local dz = z2 - z1
    return math.sqrt(dx * dx + dz * dz)
end

-- 函数：在指定位置范围内收集实体
local function CollectEntitiesInRadius(savedata_ents, center_x, center_z, radius, entity_types)
    local collected_entities = {}
    
    for _, entity_type in ipairs(entity_types) do
        if savedata_ents[entity_type] and type(savedata_ents[entity_type]) == "table" then
            for _, entity_data in ipairs(savedata_ents[entity_type]) do
                if entity_data and entity_data.x and entity_data.z then
                    local dist = Distance(center_x, center_z, entity_data.x, entity_data.z)
                    if dist <= radius then
                        table.insert(collected_entities, {
                            prefab = entity_type,
                            data = entity_data,
                            relative_x = entity_data.x - center_x,
                            relative_z = entity_data.z - center_z,
                            distance = dist
                        })
                    end
                end
            end
        end
    end
    
    return collected_entities
end

-- 函数：收集猪王周围的地板tile数据
local function CollectGroundTiles(map, center_x, center_z, radius, savedata)
    if not map then
        return nil
    end
    
    local ground_tiles = {}
    local map_width = savedata.map.width
    local map_height = savedata.map.height
    
    -- 将世界坐标转换为tile坐标
    local function WorldToTileCoords(x, z)
        local tile_x = x / TILE_SCALE + map_width / 2.0
        local tile_z = z / TILE_SCALE + map_height / 2.0
        return math.floor(tile_x), math.floor(tile_z)
    end
    
    local center_tile_x, center_tile_z = WorldToTileCoords(center_x, center_z)
    
    -- 计算需要扫描的tile范围（半径转换为tile数量）
    -- 源码布局：32x32 tiles (tilewidth=16)，实际转换为8x8 tiles = 32单位
    -- 我们使用30单位半径，约7.5个tile，覆盖整个布局（32单位对角线的一半约22.6单位）
    -- 注意：radius是单位，需要转换为tile数量
    -- 1 tile = 4单位，所以 radius单位 ÷ 4 = radius_tiles
    local radius_tiles = math.ceil(radius / TILE_SCALE)
    
    print("World Gen Mod: Collecting ground tiles in radius " .. radius .. " units (" .. radius_tiles .. " tiles)")
    print("World Gen Mod: TILE_SCALE = " .. TILE_SCALE .. ", radius_tiles calculation: " .. radius .. " / " .. TILE_SCALE .. " = " .. radius_tiles)
    
    -- 扫描范围内的所有tile
    local tiles_scanned = 0
    for dz = -radius_tiles, radius_tiles do
        for dx = -radius_tiles, radius_tiles do
            local tile_x = center_tile_x + dx
            local tile_z = center_tile_z + dz
            
            -- 检查是否在地图范围内
            if tile_x >= 0 and tile_x < map_width and tile_z >= 0 and tile_z < map_height then
                -- 计算世界坐标
                local world_x = (tile_x - map_width / 2.0) * TILE_SCALE
                local world_z = (tile_z - map_height / 2.0) * TILE_SCALE
                
                -- 检查是否在半径内（圆形区域）
                local dist = Distance(center_x, center_z, world_x, world_z)
                if dist <= radius then
                    tiles_scanned = tiles_scanned + 1
                    -- 获取tile类型
                    local tile_type = map:GetTileAtPoint(world_x, 0, world_z)
                    if tile_type then
                        table.insert(ground_tiles, {
                            tile_x = tile_x,
                            tile_z = tile_z,
                            world_x = world_x,
                            world_z = world_z,
                            tile_type = tile_type,
                            relative_x = world_x - center_x,
                            relative_z = world_z - center_z
                        })
                    end
                end
            end
        end
    end
    
    print("World Gen Mod: Scanned " .. tiles_scanned .. " tiles in radius, collected " .. #ground_tiles .. " ground tiles")
    
    return ground_tiles
end

-- 函数：通用布局收集函数（基于位置范围）
-- 参数：layout_type - 布局类型（如"pigking"、"beequeen"）
-- 返回：包含所有布局的列表，每个布局包含 entities 和 ground_tiles
local function CollectAllLayouts(layout_type, savedata_ents, map, savedata)
    local all_layouts = {}
    
    -- 获取布局配置
    local config = LAYOUT_CONFIGS[layout_type]
    if not config then
        print("World Gen Mod: ERROR - Unknown layout type: " .. tostring(layout_type))
        return all_layouts
    end
    
    local center_entity = config.center_entity
    local related_entities = config.related_entities
    local radius_entities = config.radius_entities
    local radius_ground = config.radius_ground
    
    -- 检查中心实体是否存在
    if not savedata_ents[center_entity] or type(savedata_ents[center_entity]) ~= "table" then
        print("World Gen Mod: No " .. center_entity .. " entities in savedata")
        return all_layouts
    end
    
    print("World Gen Mod: Found " .. #savedata_ents[center_entity] .. " " .. center_entity .. " entity(ies) in savedata")
    
    -- 为每个中心实体收集周围范围内的所有相关实体和地板
    for _, center_data in ipairs(savedata_ents[center_entity]) do
        if center_data and center_data.x and center_data.z then
            local center_x = center_data.x
            local center_z = center_data.z
            
            print("World Gen Mod: Collecting entities around " .. center_entity .. " at (" .. center_x .. ", " .. center_z .. ")")
            
            -- 在指定半径内收集所有相关实体
            local collected_entities = CollectEntitiesInRadius(
                savedata_ents, 
                center_x, 
                center_z, 
                radius_entities, 
                related_entities
            )
            
            -- 收集地板tile数据
            local ground_tiles = nil
            if map and savedata then
                ground_tiles = CollectGroundTiles(map, center_x, center_z, radius_ground, savedata)
                if ground_tiles then
                    print("World Gen Mod: Collected " .. #ground_tiles .. " ground tiles around " .. center_entity)
                end
            end
            
            -- 至少要有中心实体本身
            if #collected_entities > 0 then
                -- 按prefab类型分组统计
                local entity_counts = {}
                for _, ent in ipairs(collected_entities) do
                    entity_counts[ent.prefab] = (entity_counts[ent.prefab] or 0) + 1
                end
                
                local entity_summary = {}
                for prefab, count in pairs(entity_counts) do
                    table.insert(entity_summary, prefab .. ":" .. count)
                end
                
                print("World Gen Mod: Collected " .. #collected_entities .. " entities around " .. center_entity .. ": " .. table.concat(entity_summary, ", "))
                
                table.insert(all_layouts, {
                    entities = collected_entities,
                    ground_tiles = ground_tiles,  -- 地板tile数据
                    layout_def = nil,  -- 不再使用布局定义
                    layout_name = layout_type,  -- 布局类型名称
                    center_x = center_x,
                    center_z = center_z
                })
            else
                print("World Gen Mod: Warning - No entities found around " .. center_entity .. " at (" .. center_x .. ", " .. center_z .. ")")
            end
        end
    end
    
    print("World Gen Mod: Total " .. #all_layouts .. " " .. layout_type .. " layouts collected.")
    return all_layouts
end

-- 函数：收集所有猪王布局信息（基于位置范围）
-- 返回：包含所有猪王布局的列表，每个布局包含 entities 和 ground_tiles
local function CollectAllPigkingLayouts(savedata_ents, map, savedata)
    return CollectAllLayouts("pigking", savedata_ents, map, savedata)
end

-- 函数：收集所有蜂后布局信息（基于位置范围）
-- 返回：包含所有蜂后布局的列表，每个布局包含 entities 和 ground_tiles
local function CollectAllBeequeenLayouts(savedata_ents, map, savedata)
    return CollectAllLayouts("beequeen", savedata_ents, map, savedata)
end

-- 函数：在savedata中收集猪王布景的所有实体（使用布局定义）
-- 保留此函数以保持向后兼容，但推荐使用 CollectAllPigkingLayouts
-- 返回：layout_entities（实体列表）和 layout_def（布局定义，包含ground数据）
local function CollectPigkingLayoutFromSavedata(savedata_ents, pigking_x, pigking_z)
    local layout_entities = {}
    
    -- 尝试加载两种可能的猪王布局
    local layout_names = {"DefaultPigking", "TorchPigking"}
    local layout_def = nil
    local layout_name = nil
    
    for _, name in ipairs(layout_names) do
        local temp_layout = LoadLayoutDefinition(name)
        if temp_layout and temp_layout.layout and temp_layout.layout.pigking then
            -- 检查这个布局是否有猪王
            layout_def = temp_layout
            layout_name = name
            break
        end
    end
    
    if not layout_def or not layout_def.layout then
        print("World Gen Mod: Warning - Could not load pigking layout definition")
        return {}, nil
    end
    
    print("World Gen Mod: Using layout definition: " .. tostring(layout_name))
    
    -- 首先找到猪王实体
    local pigking_data = nil
    if savedata_ents.pigking and type(savedata_ents.pigking) == "table" then
        for _, pk_data in ipairs(savedata_ents.pigking) do
            if pk_data and pk_data.x and pk_data.z then
                if math.abs(pk_data.x - pigking_x) < 0.1 and math.abs(pk_data.z - pigking_z) < 0.1 then
                    pigking_data = pk_data
                    break
                end
            end
        end
    end
    
    if not pigking_data then
        print("World Gen Mod: Warning - Could not find pigking entity at (" .. pigking_x .. ", " .. pigking_z .. ")")
        return {}, nil
    end
    
    -- 添加猪王
    table.insert(layout_entities, {
        prefab = "pigking",
        data = pigking_data,
        relative_x = 0,
        relative_z = 0
    })
    
    -- 根据布局定义查找其他实体
    -- 布局定义中的位置是相对于布局中心的（以tile为单位）
    -- 需要转换为世界坐标
    for prefab_name, prefab_positions in pairs(layout_def.layout) do
        if prefab_name ~= "pigking" and type(prefab_positions) == "table" then
            for _, pos_data in ipairs(prefab_positions) do
                -- pos_data.x 和 pos_data.y 是相对于布局中心的tile坐标
                -- 需要转换为世界坐标
                local expected_world_x = pigking_x + pos_data.x * TILE_SCALE
                local expected_world_z = pigking_z + pos_data.y * TILE_SCALE
                
                -- 在savedata中查找匹配的实体（允许小误差）
                local tolerance = 0.5 -- 允许0.5单位的误差
                if savedata_ents[prefab_name] and type(savedata_ents[prefab_name]) == "table" then
                    for _, entity_data in ipairs(savedata_ents[prefab_name]) do
                        if entity_data and entity_data.x and entity_data.z then
                            local dx = math.abs(entity_data.x - expected_world_x)
                            local dz = math.abs(entity_data.z - expected_world_z)
                            
                            if dx < tolerance and dz < tolerance then
                                -- 找到匹配的实体
                                table.insert(layout_entities, {
                                    prefab = prefab_name,
                                    data = entity_data,
                                    relative_x = pos_data.x * TILE_SCALE,
                                    relative_z = pos_data.y * TILE_SCALE
                                })
                                break -- 找到后跳出，避免重复
                            end
                        end
                    end
                end
            end
        end
    end
    
    print("World Gen Mod: Collected " .. #layout_entities .. " entities from layout definition")
    if layout_def.ground then
        print("World Gen Mod: Layout includes " .. #layout_def.ground .. "x" .. (#layout_def.ground[1] or 0) .. " ground tiles")
    end
    return layout_entities, layout_def
end

-- 导出到全局变量（因为modimport不支持返回值）
WorldGenMod_LayoutCollection = {
    CollectPigkingLayoutFromSavedata = CollectPigkingLayoutFromSavedata,
    CollectAllPigkingLayouts = CollectAllPigkingLayouts,
    CollectAllBeequeenLayouts = CollectAllBeequeenLayouts,
    CollectAllLayouts = CollectAllLayouts,  -- 通用函数
}

