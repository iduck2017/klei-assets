-- Task 过滤器 Hook
-- 用于移除特定的 task，防止它们在地图生成中出现

-- 配置：要移除的 task 名称列表（不区分大小写）
local TASKS_TO_REMOVE = {
    -- 包含三只海象的 task
    "Guarded Walrus Desolate",  -- 包含3个海象小屋
    "Walrus Desolate",          -- 包含3个海象小屋
    "Waspy The hunters",        -- 包含3个海象小屋
    
    -- 包含非常多池塘的 task
    "Hounded Magic meadow",     -- 包含2个 Pondopolis 房间（每个5-8个池塘，总共10-16个池塘）
    
    -- 其他要移除的 task（示例）
    -- "Make a pick",
    -- "Dig that rock",
    -- "Speak to the king",
}

-- 将 task 名称转换为小写用于比较
local function NormalizeTaskName(name)
    return name and string.lower(tostring(name)) or ""
end

-- 检查 task 是否应该被移除
local function ShouldRemoveTask(task_name)
    if not task_name then
        return false
    end
    local normalized = NormalizeTaskName(task_name)
    for _, task_to_remove in ipairs(TASKS_TO_REMOVE) do
        if normalized == NormalizeTaskName(task_to_remove) then
            return true
        end
    end
    return false
end

-- 从数组中移除指定的 task
local function RemoveTasksFromArray(tasks_array)
    if not tasks_array or type(tasks_array) ~= "table" then
        return
    end
    
    local removed_count = 0
    local i = 1
    while i <= #tasks_array do
        local task = tasks_array[i]
        local task_name = task
        
        -- 处理 table 格式的 task（如 optionaltasks 中的嵌套数组）
        if type(task) == "table" then
            -- 如果是嵌套数组，递归处理
            local nested_removed = RemoveTasksFromArray(task)
            if nested_removed > 0 then
                removed_count = removed_count + nested_removed
            end
            -- 如果嵌套数组为空，移除它
            if #task == 0 then
                table.remove(tasks_array, i)
            else
                i = i + 1
            end
        else
            -- 普通 task 名称
            if ShouldRemoveTask(task_name) then
                table.remove(tasks_array, i)
                removed_count = removed_count + 1
                print(string.format("[Task Filter] 已移除 task: '%s'", task_name))
            else
                i = i + 1
            end
        end
    end
    
    return removed_count
end

-- 安装 Task Set PreInit Hook（对所有 task set 生效）
local function InstallTaskFilterHook()
    -- 使用 AddTaskSetPreInitAny 对所有 task set 生效
    if AddTaskSetPreInitAny then
        AddTaskSetPreInitAny(function(task_set_data)
            if not task_set_data then
                return
            end
            
            local removed_count = 0
            
            -- 移除 tasks 数组中的 task
            if task_set_data.tasks then
                local count = RemoveTasksFromArray(task_set_data.tasks)
                removed_count = removed_count + count
            end
            
            -- 移除 optionaltasks 数组中的 task
            if task_set_data.optionaltasks then
                local count = RemoveTasksFromArray(task_set_data.optionaltasks)
                removed_count = removed_count + count
            end
            
            -- 移除 valid_start_tasks 数组中的 task
            if task_set_data.valid_start_tasks then
                local count = RemoveTasksFromArray(task_set_data.valid_start_tasks)
                removed_count = removed_count + count
            end
            
            if removed_count > 0 then
                print(string.format(
                    "[Task Filter] 从 task set '%s' 中移除了 %d 个 task",
                    task_set_data.name or "unknown",
                    removed_count
                ))
            end
        end)
        print("[Task Filter] Task 过滤器 Hook 已安装")
    else
        print("[Task Filter] ⚠️  AddTaskSetPreInitAny 不可用，Task 过滤器未安装")
    end
end

return InstallTaskFilterHook

