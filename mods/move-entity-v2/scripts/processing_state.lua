-- ProcessingState 模块：管理 layout 处理状态
-- 用于在 layout_hook 和 prefab_hook 之间共享状态，避免 layout 中的 prefab 被重复处理

local ProcessingState = {}

-- 内部状态：是否正在处理一个 layout
local is_processing_layout = false

-- 设置是否正在处理 layout
function ProcessingState.SetProcessing(value)
    is_processing_layout = value
end

-- 获取是否正在处理 layout
function ProcessingState.IsProcessing()
    return is_processing_layout
end

return ProcessingState

