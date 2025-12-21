-- 海岸检测模块
-- 用于检测和查找海岸位置

-- 确保常量已加载
if not WorldGenMod_Constants then
    error("WorldGenMod_Constants not loaded! Make sure constants.lua is imported first.")
end

local TILE_SCALE = WorldGenMod_Constants.TILE_SCALE
local MAX_SEARCH_RADIUS = WorldGenMod_Constants.MAX_SEARCH_RADIUS

-- 函数：通过tile类型检查位置是否在海边（陆地tile且附近有海洋tile）
local function IsCoastPosition(x, z, map, savedata)
    if not map then
        return false
    end
    
    -- 检查当前位置是否是陆地tile（使用Map API）
    if not map:IsLandTileAtPoint(x, 0, z) then
        return false
    end
    
    -- 检查周围是否有海洋tile（检查8个方向）
    local check_radius = TILE_SCALE * 2 -- 检查周围2个tile的距离
    local directions = {
        {check_radius, 0},      -- 右
        {-check_radius, 0},     -- 左
        {0, check_radius},      -- 上
        {0, -check_radius},     -- 下
        {check_radius, check_radius},    -- 右上
        {-check_radius, check_radius},   -- 左上
        {check_radius, -check_radius},   -- 右下
        {-check_radius, -check_radius},  -- 左下
    }
    
    for _, dir in ipairs(directions) do
        local check_x = x + dir[1]
        local check_z = z + dir[2]
        if map:IsOceanTileAtPoint(check_x, 0, check_z) then
            return true
        end
    end
    
    return false
end

-- 函数：查找最近的海边位置（仅使用tile类型判断，无备用方案）
local function FindNearestCoastPosition(original_x, original_z, search_radius, map, savedata)
    search_radius = search_radius or MAX_SEARCH_RADIUS
    
    -- 必须使用Map对象来检查tile类型，没有备用方案
    if not map then
        print("World Gen Mod: ERROR - TheWorld.Map is not available!")
        print("World Gen Mod: ERROR - Cannot accurately detect coast without Map API")
        print("World Gen Mod: ERROR - TheWorld: " .. tostring(TheWorld ~= nil))
        if TheWorld then
            print("World Gen Mod: ERROR - TheWorld.Map: " .. tostring(TheWorld.Map ~= nil))
        end
        print("World Gen Mod: ERROR - Returning original position, pigking will not be moved")
        return original_x, original_z
    end
    
    print("World Gen Mod: Using tile-based coast detection with TheWorld.Map")
    
    -- 使用tile-based方法查找海边
    -- 采用"由近到远"的同心圆搜索策略，找到第一个海岸位置就是最近的
    
    local search_step = TILE_SCALE * 2  -- 每2个tile检查一次
    local max_radius_tiles = math.ceil(search_radius / search_step)
    local num_angles = 16  -- 16个方向
    
    print("World Gen Mod: Searching for nearest coast from (" .. original_x .. ", " .. original_z .. ")")
    print("World Gen Mod: Search radius: " .. search_radius .. ", step: " .. search_step .. ", max radius tiles: " .. max_radius_tiles)
    print("World Gen Mod: Using concentric circle search (near to far)")
    
    local checked_positions = 0
    
    -- 由近到远搜索：先搜索距离1，再搜索距离2，以此类推
    -- 一旦找到海岸位置，立即返回（因为是从近到远，第一个就是最近的）
    for radius_mult = 1, max_radius_tiles do
        local distance = radius_mult * search_step
        
        -- 在当前距离的圆周上均匀采样16个点
        for angle_idx = 0, num_angles - 1 do
            local angle = (angle_idx / num_angles) * 2 * math.pi
            local check_x = original_x + math.cos(angle) * distance
            local check_z = original_z + math.sin(angle) * distance
            
            checked_positions = checked_positions + 1
            
            -- 检查是否是海边位置
            if IsCoastPosition(check_x, check_z, map, savedata) then
                local dist = math.sqrt((check_x - original_x)^2 + (check_z - original_z)^2)
                print("World Gen Mod: Found nearest coast at (" .. check_x .. ", " .. check_z .. "), distance: " .. dist)
                print("World Gen Mod: Checked " .. checked_positions .. " positions before finding coast")
                return check_x, check_z
            end
        end
    end
    
    -- 如果搜索完所有位置都没找到海岸
    print("World Gen Mod: ERROR - No coast position found within search radius!")
    print("World Gen Mod: ERROR - Checked " .. checked_positions .. " positions but found no valid coast")
    print("World Gen Mod: ERROR - Returning original position, pigking will not be moved")
    return original_x, original_z
end

-- 导出到全局变量（因为modimport不支持返回值）
WorldGenMod_CoastDetection = {
    IsCoastPosition = IsCoastPosition,
    FindNearestCoastPosition = FindNearestCoastPosition,
}

