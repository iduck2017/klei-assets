-- 布局移动模块
-- 负责移动布局到海边位置（支持多种布局类型）

-- 确保依赖模块已加载
if not WorldGenMod_Constants then
    error("WorldGenMod_Constants not loaded! Make sure constants.lua is imported first.")
end
if not WorldGenMod_CoastDetection then
    error("WorldGenMod_CoastDetection not loaded! Make sure coast_detection.lua is imported first.")
end
if not WorldGenMod_LayoutCollection then
    error("WorldGenMod_LayoutCollection not loaded! Make sure layout_collection.lua is imported first.")
end

local MAX_SEARCH_RADIUS = WorldGenMod_Constants.MAX_SEARCH_RADIUS
local TILE_SCALE = WorldGenMod_Constants.TILE_SCALE
local FindNearestCoastPosition = WorldGenMod_CoastDetection.FindNearestCoastPosition

-- 函数：移动布局的地板tile（使用布局定义）
local function MoveLayoutGroundTilesFromDef(map, layout_def, old_x, old_z, new_x, new_z, savedata)
    if not layout_def.ground or not layout_def.ground_types then
        return
    end
    
    local layout_size = #layout_def.ground
    if layout_size == 0 then
        return
    end
    
    print("World Gen Mod: Moving " .. layout_size .. "x" .. layout_size .. " ground tiles from layout definition")
    
    -- 计算tile坐标偏移（以tile为单位）
    local map_width = savedata.map.width
    local map_height = savedata.map.height
    
    -- 将世界坐标转换为tile坐标
    local function WorldToTileCoords(x, z)
        local tile_x = x / TILE_SCALE + map_width / 2.0
        local tile_z = z / TILE_SCALE + map_height / 2.0
        return math.floor(tile_x), math.floor(tile_z)
    end
    
    local old_tile_x, old_tile_z = WorldToTileCoords(old_x, old_z)
    local new_tile_x, new_tile_z = WorldToTileCoords(new_x, new_z)
    
    -- 布局中心在布局的中间位置
    local layout_center_offset = math.floor(layout_size / 2)
    
    -- 移动每个tile
    local tiles_moved = 0
    for row = 1, layout_size do
        for col = 1, layout_size do
            local tile_type_idx = layout_def.ground[row][col]
            if tile_type_idx and tile_type_idx ~= 0 then
                local tile_type = layout_def.ground_types[tile_type_idx]
                if tile_type then
                    -- 计算原始tile位置（相对于布局中心）
                    local rel_x = col - layout_center_offset - 1
                    local rel_z = row - layout_center_offset - 1
                    
                    -- 新位置
                    local new_tile_pos_x = new_tile_x + rel_x
                    local new_tile_pos_z = new_tile_z + rel_z
                    
                    -- 检查新位置是否在地图范围内
                    if new_tile_pos_x >= 0 and new_tile_pos_x < map_width and 
                       new_tile_pos_z >= 0 and new_tile_pos_z < map_height then
                        -- 设置新位置的tile
                        map:SetTile(new_tile_pos_x, new_tile_pos_z, tile_type, 1)
                        tiles_moved = tiles_moved + 1
                    end
                end
            end
        end
    end
    
    print("World Gen Mod: Moved " .. tiles_moved .. " ground tiles from layout definition")
    
    -- 更新savedata.map.tiles（重要！）
    savedata.map.tiles = map:GetStringEncode()
    savedata.map.nodeidtilemap = map:GetNodeIdTileMapStringEncode()
end

-- 函数：移动地板tile（使用收集的ground_tiles数据）
local function MoveGroundTiles(map, ground_tiles, old_x, old_z, new_x, new_z, savedata)
    if not ground_tiles or #ground_tiles == 0 then
        return
    end
    
    if not map then
        print("World Gen Mod: Warning - Map not available, cannot move ground tiles")
        return
    end
    
    print("World Gen Mod: Moving " .. #ground_tiles .. " ground tiles")
    
    local map_width = savedata.map.width
    local map_height = savedata.map.height
    
    -- 将世界坐标转换为tile坐标
    local function WorldToTileCoords(x, z)
        local tile_x = x / TILE_SCALE + map_width / 2.0
        local tile_z = z / TILE_SCALE + map_height / 2.0
        return math.floor(tile_x), math.floor(tile_z)
    end
    
    local tiles_moved = 0
    
    -- 计算位置偏移
    local offset_x = new_x - old_x
    local offset_z = new_z - old_z
    
    -- 移动每个tile
    for _, tile_data in ipairs(ground_tiles) do
        -- 计算新位置的世界坐标
        local new_world_x = tile_data.world_x + offset_x
        local new_world_z = tile_data.world_z + offset_z
        
        -- 转换为tile坐标
        local new_tile_x, new_tile_z = WorldToTileCoords(new_world_x, new_world_z)
        
        -- 检查新位置是否在地图范围内
        if new_tile_x >= 0 and new_tile_x < map_width and 
           new_tile_z >= 0 and new_tile_z < map_height then
            -- 设置新位置的tile
            map:SetTile(new_tile_x, new_tile_z, tile_data.tile_type, 1)
            tiles_moved = tiles_moved + 1
        end
    end
    
    print("World Gen Mod: Moved " .. tiles_moved .. " ground tiles")
    
    -- 更新savedata.map.tiles（重要！）
    savedata.map.tiles = map:GetStringEncode()
    savedata.map.nodeidtilemap = map:GetNodeIdTileMapStringEncode()
end

-- 函数：通用布局移动函数
-- 参数：layout_type - 布局类型（如"pigking"、"beequeen"）
--        collect_function - 收集函数（如CollectAllPigkingLayouts）
local function MoveLayoutToCoast(layout_type, collect_function, savedata, map)
    -- 检查savedata结构
    if not savedata or not savedata.ents or not savedata.map or not savedata.map.topology then
        print("World Gen Mod: Invalid savedata structure")
        return
    end
    
    -- 获取布局配置，检查是否需要移动地皮
    local config = WorldGenMod_Constants.LAYOUT_CONFIGS[layout_type]
    local move_ground = config and config.move_ground ~= false  -- 默认为true，除非明确设置为false
    
    -- 第一步：收集所有布局（包括实体和地板tile）
    print("World Gen Mod: Collecting all " .. layout_type .. " layouts...")
    local all_layouts = collect_function(savedata.ents, map, savedata)
    
    if #all_layouts == 0 then
        print("World Gen Mod: No " .. layout_type .. " layouts found")
        return
    end
    
    print("World Gen Mod: Found " .. #all_layouts .. " " .. layout_type .. " layout(s)")
    
    -- 第二步：移动每个布局
    local moved_layouts = 0
    local map_width = savedata.map.width
    local map_height = savedata.map.height
    
    -- tile中心计算函数（复用）
    local function GetTileCenter(x, z)
        -- 将世界坐标转换为tile坐标（使用与WorldToTileCoords相同的逻辑）
        local tile_x = x / TILE_SCALE + map_width / 2.0
        local tile_z = z / TILE_SCALE + map_height / 2.0
        
        -- 取整得到tile索引（使用math.floor，不是math.floor + 0.5）
        local tile_idx_x = math.floor(tile_x)
        local tile_idx_z = math.floor(tile_z)
        
        -- 将tile索引转换回世界坐标（tile中心 = tile索引 + 0.5，然后转换回世界坐标）
        -- tile中心 = (tile_idx + 0.5 - map_width/2) * TILE_SCALE
        local tile_center_x = (tile_idx_x + 0.5 - map_width / 2.0) * TILE_SCALE
        local tile_center_z = (tile_idx_z + 0.5 - map_height / 2.0) * TILE_SCALE
        
        return tile_center_x, tile_center_z
    end
    
    for _, layout_info in ipairs(all_layouts) do
        local layout_entities = layout_info.entities
        local layout_def = layout_info.layout_def
        local original_x = layout_info.center_x
        local original_z = layout_info.center_z
        
        print("World Gen Mod: Processing " .. layout_type .. " layout '" .. layout_info.layout_name .. "' at (" .. original_x .. ", " .. original_z .. ") with " .. #layout_entities .. " entities")
        
        -- 查找最近的海边位置（仅使用Map API检查tile类型）
        print("World Gen Mod: Searching for nearest coast position from (" .. original_x .. ", " .. original_z .. ")...")
        if map then
            print("World Gen Mod: Using world_map API for tile-based coast detection")
            -- 测试读取原始位置的tile
            local original_tile = map:GetTileAtPoint(original_x, 0, original_z)
            local is_land = map:IsLandTileAtPoint(original_x, 0, original_z)
            print("World Gen Mod: Original position tile: " .. tostring(original_tile) .. " (IsLand: " .. tostring(is_land) .. ")")
        else
            print("World Gen Mod: ERROR - world_map not available, cannot detect coast accurately")
        end
        
        -- 计算中心实体相对于所在tile的位置偏移（tile内的偏移量）
        -- 确保移动后保持相同的tile内相对位置
        local original_tile_center_x, original_tile_center_z = GetTileCenter(original_x, original_z)
        local tile_offset_x = original_x - original_tile_center_x
        local tile_offset_z = original_z - original_tile_center_z
        
        print("World Gen Mod: " .. layout_type .. " at (" .. original_x .. ", " .. original_z .. "), tile center at (" .. original_tile_center_x .. ", " .. original_tile_center_z .. "), tile offset (" .. tile_offset_x .. ", " .. tile_offset_z .. ")")
        
        -- 查找最近的海边位置（返回tile中心位置）
        local new_tile_center_x, new_tile_center_z = FindNearestCoastPosition(original_tile_center_x, original_tile_center_z, MAX_SEARCH_RADIUS, map, savedata)
        
        -- 计算新位置：新tile中心 + 原来的tile内偏移量
        local new_x = new_tile_center_x + tile_offset_x
        local new_z = new_tile_center_z + tile_offset_z
        
        print("World Gen Mod: New tile center at (" .. new_tile_center_x .. ", " .. new_tile_center_z .. "), new " .. layout_type .. " position (" .. new_x .. ", " .. new_z .. ")")
        
        -- 计算位置偏移
        local offset_x = new_x - original_x
        local offset_z = new_z - original_z
        
        -- 只有在位置真的改变时才移动
        if offset_x ~= 0 or offset_z ~= 0 then
            print("World Gen Mod: Moving " .. layout_type .. " layout from (" .. original_x .. ", " .. original_z .. ") to coast at (" .. new_x .. ", " .. new_z .. ")")
            
            -- 移动所有实体到新位置，保持相对位置
            for _, entity_info in ipairs(layout_entities) do
                if not entity_info or not entity_info.data then
                    print("World Gen Mod: Warning - Invalid entity_info, skipping")
                else
                    -- 保存原始位置用于日志
                    local old_entity_x = entity_info.data.x
                    local old_entity_z = entity_info.data.z
                    
                    -- 计算新位置
                    local new_entity_x = old_entity_x + offset_x
                    local new_entity_z = old_entity_z + offset_z
                    
                    -- 更新savedata中的位置（直接修改引用）
                    entity_info.data.x = new_entity_x
                    entity_info.data.z = new_entity_z
                    
                    print("World Gen Mod: Moved " .. entity_info.prefab .. " from (" .. 
                          old_entity_x .. ", " .. old_entity_z .. 
                          ") to (" .. new_entity_x .. ", " .. new_entity_z .. ")")
                end
            end
            
            -- 移动地板tile（根据配置决定是否移动）
            if move_ground then
                if layout_info.ground_tiles and map then
                    -- 使用收集的ground_tiles数据
                    MoveGroundTiles(map, layout_info.ground_tiles, original_x, original_z, new_x, new_z, savedata)
                elseif layout_def and layout_def.ground and layout_def.ground_types and map then
                    -- 使用布局定义中的ground数据
                    MoveLayoutGroundTilesFromDef(map, layout_def, original_x, original_z, new_x, new_z, savedata)
                else
                    print("World Gen Mod: No ground data available, skipping ground tile movement")
                end
            else
                print("World Gen Mod: Skipping ground tile movement for " .. layout_type .. " (move_ground = false)")
            end
            
            moved_layouts = moved_layouts + 1
        else
            print("World Gen Mod: " .. layout_type .. " is already at coast position, no move needed")
        end
    end
    
    if moved_layouts > 0 then
        print("World Gen Mod: Successfully moved " .. moved_layouts .. " " .. layout_type .. " layout(s) to coast in savedata")
    else
        print("World Gen Mod: No " .. layout_type .. " layouts needed to be moved (all are already at coast)")
    end
end

-- 函数：移动猪王到海边
local function MovePigkingToCoast(savedata, map)
    MoveLayoutToCoast("pigking", WorldGenMod_LayoutCollection.CollectAllPigkingLayouts, savedata, map)
end

-- 函数：移动蜂后到海边
local function MoveBeequeenToCoast(savedata, map)
    MoveLayoutToCoast("beequeen", WorldGenMod_LayoutCollection.CollectAllBeequeenLayouts, savedata, map)
end

-- 导出到全局变量（因为modimport不支持返回值）
WorldGenMod_PigkingMover = {
    MovePigkingToCoast = MovePigkingToCoast,
    MoveBeequeenToCoast = MoveBeequeenToCoast,
    MoveLayoutToCoast = MoveLayoutToCoast,  -- 通用函数
}

