# Task Filter Mod

一个用于移除指定 task 的 Don't Starve Together 模组。

## 功能

这个 mod 允许你在地图生成时移除特定的 task，防止它们出现在游戏中。

## 使用方法

1. 编辑 `scripts/task_filter_hook.lua` 文件
2. 在 `TASKS_TO_REMOVE` 列表中添加要移除的 task 名称：

```lua
local TASKS_TO_REMOVE = {
    "Make a pick",        -- 移除"制作镐子"任务
    "Dig that rock",      -- 移除"挖掘石头"任务
    "Speak to the king",  -- 移除"与国王对话"任务
    -- 添加更多要移除的 task 名称...
}
```

## 工作原理

- 使用 `AddTaskSetPreInitAny` hook，在所有 task set 初始化时执行
- 从以下数组中移除指定的 task：
  - `tasks` - 必需任务列表
  - `optionaltasks` - 可选任务列表
  - `valid_start_tasks` - 有效起始任务列表
- 支持嵌套数组（如 `optionaltasks` 中的 table 格式）
- 不区分大小写匹配

## 查看可用的 task 名称

可以查看以下文件了解可用的 task：
- `src/map/tasksets/forest.lua` - 森林世界的 task
- `src/map/tasksets/caves.lua` - 洞穴世界的 task
- `src/map/tasks/` 目录下的其他文件

## 注意事项

- 移除 task 可能会影响地图生成的结构和游戏体验
- 确保移除的 task 不是其他 task 的依赖（通过 locks 和 keys_given 系统）
- 建议在测试服务器上先测试配置

ThePlayer.components.talker:Say(string.format("%s世界: %d x %d", TheShard:IsSecondary() and "洞穴" or "地面", (function() local w, h = TheWorld.Map:GetSize() return w, h end)()))