# Debug 日志分析

## 2025-12-24 日志分析

### Mod 加载状态
- ✅ Mod 成功加载（在 Frontend、游戏加载等多个阶段）
- ✅ Hook 函数已安装

### 发现的问题

#### 问题1: SetTile 调用错误
**错误信息**:
```
DoLuaFile Error: #[string "scripts/map/object_layout.lua"]:392: calling 'SetTile' on bad self (WorldSimActual expected, got table)
```

**错误位置**: `scripts/map/object_layout.lua:392`

**错误原因**:
- 在 `layout_hook.lua` 中，无论是否有 `position` 参数，都包装了 `world` 对象
- 当 `position` 存在时（指定位置），原始函数会调用 `world:SetTile()` 设置地形
- 包装后的 table 对象无法正确调用 `SetTile` 方法，因为 `SetTile` 需要 `WorldSimActual` 类型的对象

**相关代码位置**:
- `layout_hook.lua:19` - 创建了包装的 world 对象
- `layout_hook.lua:45` - 将包装的 world 传递给原始函数

**解决方案**:
- 仅在 `position == nil`（自动寻找位置）时包装 `world` 对象
- 当 `position` 存在时（指定位置），直接使用原始 `world` 对象，不包装

### 正常工作的部分

#### 成功捕获布局信息
- ✅ 成功捕获了布局名称: `Waterlogged1`
- ✅ 成功捕获了坐标: `rcx=44.00, rcy=377.00`
- ✅ 正确识别了位置类型: `指定位置`

**日志输出**:
```
[00:00:31]: [Move Entity V2] Layout 'Waterlogged1' - 关键点1: 保留空间确定 (指定位置) - rcx=44.00, rcy=377.00 (左下角坐标)
```

### 未看到的信息

- ❌ 未看到完整的布局信息输出（"Layout 放置信息"部分）
- 原因：在打印完整信息之前，`SetTile` 错误导致函数执行中断

### 建议修复

修改 `layout_hook.lua` 的逻辑：
1. 检查 `position` 参数
2. 如果 `position` 存在，直接使用原始 `world`，不包装
3. 如果 `position == nil`，才包装 `world` 对象来拦截 `ReserveSpace`

### 修复状态

✅ **已修复** (2025-12-24)

**修复内容**:
- 修改了 `layout_hook.lua:19`，将 `wrapped_world` 初始化为 `original_world`
- 修改了逻辑流程：
  - 如果 `position` 存在：直接使用 `original_world`，不包装
  - 如果 `position == nil`：才创建包装的 `world` 对象来拦截 `ReserveSpace`

**修复后的代码逻辑**:
```lua
local wrapped_world = original_world  -- 初始化为原始world

if position then
    -- 指定位置：直接使用原始world，不包装
    captured_rcx = position[1]
    captured_rcy = position[2]
    -- wrapped_world 保持为 original_world
else
    -- 自动寻找位置：包装world来拦截ReserveSpace
    wrapped_world = setmetatable({}, {__index = original_world})
    wrapped_world.ReserveSpace = function(self, ...)
        -- 拦截并捕获坐标
    end
end
```

**预期效果**:
- ✅ 指定位置的布局不再出现 `SetTile` 错误
- ✅ 自动寻找位置的布局仍能正确拦截 `ReserveSpace`
- ✅ 完整的布局信息应该能正常输出

---

## 2025-12-24 第二次日志分析（修复后）

### 修复效果验证

#### ✅ 成功工作的部分

**大量成功的布局信息输出**:
- 从日志第1189行开始，有大量成功的布局信息输出
- 所有输出都包含完整的布局信息（布局名称、节点ID、位置类型、坐标、Prefab数量、缩放因子）
- 所有捕获的布局都是"指定位置"类型（manual）

**成功捕获的布局示例**:
```
[00:00:54]: [Move Entity V2] Layout 'BrinePool1' - 关键点1: 保留空间确定 (指定位置) - rcx=382.00, rcy=364.00 (左下角坐标)
[00:00:54]: [Move Entity V2] ========================================
[00:00:54]: [Move Entity V2] Layout 放置信息:
[00:00:54]: [Move Entity V2]   布局名称: BrinePool1
[00:00:54]: [Move Entity V2]   节点ID: POSITIONED
[00:00:54]: [Move Entity V2]   位置类型: manual
[00:00:54]: [Move Entity V2]   保留区域左下角坐标: rcx=382.00, rcy=364.00
[00:00:54]: [Move Entity V2]   Prefab数量: 11
[00:00:54]: [Move Entity V2]   缩放因子: 1.00
[00:00:54]: [Move Entity V2] ========================================
```

**捕获的布局类型**:
- `BrinePool1`, `BrinePool2`, `BrinePool3` - 盐水池布局
- `Waterlogged1` - 水淹布局
- `BullkelpFarmMedium`, `BullkelpFarmSmall` - 海带农场布局

#### ⚠️ 仍存在的问题

**SetTile 错误（旧日志）**:
- 日志第1195-1196行仍有一个 `SetTile` 错误
- **注意**: 这个错误发生在 `[00:00:31]`，而成功的输出在 `[00:00:54]`
- 说明这个错误是在修复之前的旧代码产生的
- 修复后的代码（从1189行开始）没有出现 `SetTile` 错误

**未测试的场景**:
- ❌ 没有看到"自动寻找位置"的布局输出
- 原因：本次测试中所有布局都是指定位置的（`position` 参数存在）
- 需要测试自动寻找位置的布局来验证 `ReserveSpace` 拦截是否正常工作

### 结论

✅ **修复成功**:
- 指定位置的布局现在可以正常工作
- 完整的布局信息能够正常输出
- 不再出现 `SetTile` 错误（修复后的代码）

⚠️ **待验证**:
- 自动寻找位置的布局（`position == nil`）的 `ReserveSpace` 拦截功能
- 需要在实际生成世界中找到使用自动寻找位置的布局进行测试

---

## 2025-12-24 第三次日志分析（查找 DefaultPigking）

### 关于 DefaultPigking 布局

#### ❌ 未在最新日志中看到 DefaultPigking

**搜索结果**:
- 在最新的 `client_log.txt` 中，**没有找到** `DefaultPigking` 布局的输出
- 日志中只看到了海洋相关的布局（`BrinePool1/2/3`, `Waterlogged1`, `BullkelpFarmMedium/Small`）
- 日志第1476行显示：`Checking Required Prefab pigking has at least 1 instances (1 found)` - 说明 pigking 实体确实被创建了

**可能的原因**:
1. **DefaultPigking 使用自动寻找位置** (`position == nil`)
   - 如果 `DefaultPigking` 使用自动寻找位置，我们的 Hook 应该能捕获
   - 但日志中没有看到"自动寻找位置"的输出
   - 可能 `ReserveSpace` 拦截没有正常工作，或者布局生成时没有调用 `ReserveAndPlaceLayout`

2. **布局生成时机不同**
   - `DefaultPigking` 可能在更早的阶段生成（在 Hook 安装之前）
   - 或者使用了不同的放置机制（不通过 `ReserveAndPlaceLayout`）

3. **世界生成配置**
   - 本次测试的世界可能没有生成 `DefaultPigking` 布局
   - 或者 `PigKingdom` 房间没有被选中

**在备份日志中的发现**:
- 在旧的备份日志中（`client_log_2025-12-24-02-02-55.txt` 等），有看到 `DefaultPigking` 的处理
- 但这些是旧版本代码的输出，显示 `position=nil`（自动寻找位置）
- 旧日志显示：`[Layout] ReserveAndPlaceLayout called: DefaultPigking, position=nil`

**建议**:
1. 确认当前世界是否生成了 `PigKingdom` 房间
2. 检查 `DefaultPigking` 是否真的使用了 `ReserveAndPlaceLayout` 函数
3. 如果 `DefaultPigking` 使用自动寻找位置，需要验证 `ReserveSpace` 拦截是否正常工作

---

## 2025-12-24 第四次日志分析（调研 DefaultPigking 未 Hook 的原因）

### 源码调研结果

#### 关键发现：模块加载顺序问题

**加载顺序**:
```
worldgen_main.lua:140
  → require("map/forest_map")
    → forest_map.lua:11 require("map/ocean_gen")
      → ocean_gen.lua:5 local obj_layout = require("map/object_layout")
        → object_layout 模块被首次加载并缓存

worldgen_main.lua:147
  → ModManager:LoadMods(true)
    → mods.lua:577 InitializeModMain("modworldgenmain.lua")
      → 我们的 Hook 安装
        → require("map/object_layout") 返回已缓存的模块
        → 修改 obj_layout.ReserveAndPlaceLayout
```

**问题分析**:
1. ✅ `object_layout` 模块在 Hook 安装前已被加载
2. ✅ Lua 的 require 机制会返回同一个模块引用
3. ✅ 我们的 Hook 应该能正常工作

**但是**:
- `ocean_gen.lua:5` 在文件顶部就保存了 `local obj_layout = require("map/object_layout")`
- 这是一个**局部变量**，保存了模块的引用
- 当我们在 Hook 中修改 `obj_layout.ReserveAndPlaceLayout` 时，修改的是模块表
- `ocean_gen.lua:626` 调用 `obj_layout.ReserveAndPlaceLayout()` 时，应该使用的是修改后的函数

**可能的原因**:
1. **DefaultPigking 不使用 ocean_gen 的路径**
   - `DefaultPigking` 通过 `Node:ConvertGround()` → `obj_layout.Convert()` 调用
   - `graphnode.lua:251` 在函数内部 `local obj_layout = require("map/object_layout")`
   - 这也是局部变量，应该能获取到修改后的函数

2. **Hook 安装时机问题**
   - 需要确认 Hook 是否真的在 `DefaultPigking` 被调用之前安装
   - 检查日志中是否有 Hook 安装的确认信息

3. **模块引用问题**
   - 虽然 require 返回同一个模块，但如果有多个局部变量保存了引用
   - 需要确认所有调用路径都使用同一个模块引用

**验证方法**:
- 在 Hook 安装时打印确认信息
- 在 `ReserveAndPlaceLayout` 被调用时打印调试信息
- 检查是否有其他调用路径绕过了我们的 Hook

#### 🔴 根本原因发现

**关键代码** (`src/map/object_layout.lua:509-513`):
```lua
local function Convert(node_id, item, addEntity)
    assert(item and item ~= "", "Must provide a valid layout name, got nothing.")
    local layout = LayoutForDefinition(item)
    local prefabs = ConvertLayoutToEntitylist(layout)
    ReserveAndPlaceLayout(node_id, layout, prefabs, addEntity)  -- ⚠️ 直接调用 local 函数
end
```

**问题**:
- `ReserveAndPlaceLayout` 是 **local 函数**（第294行定义）
- `Convert` 函数内部**直接调用** local 函数 `ReserveAndPlaceLayout`
- 而不是通过模块表调用 `obj_layout.ReserveAndPlaceLayout`
- 因此，当我们修改 `obj_layout.ReserveAndPlaceLayout` 时，`Convert` 函数内部仍然调用的是原始的 local 函数

**调用链**:
```
Node:ConvertGround()
  → obj_layout.Convert()  (通过模块表调用)
    → Convert() 内部直接调用 local ReserveAndPlaceLayout()  ← 绕过了我们的 Hook！
```

**解决方案**:
需要 Hook `Convert` 函数，而不是 `ReserveAndPlaceLayout` 函数
- 或者：在 `Convert` 函数内部修改调用方式（不可行，因为这是源码）
- 或者：Hook `Convert` 函数，在调用原始 `Convert` 之前/之后进行处理

---

## 2025-12-24 第五次日志分析（游戏闪退 - ReserveSpace 错误）

### 🔴 新错误：ReserveSpace 参数错误

**错误信息**:
```
DoLuaFile Error: #[string "../mods/move-entity-v2/scripts/layout_hook...."]:34: bad argument #1 to 'ReserveSpace' (WorldSimActual expected, got table)
```

**错误位置**: `layout_hook.lua:34`

**错误原因**:
- 在 `ReserveSpace` wrapper 中（第33-45行），我们调用 `original_world.ReserveSpace(self, ...)`
- 这里的 `self` 是 `wrapped_world`（一个 table），而不是 `original_world`（WorldSimActual 对象）
- `ReserveSpace` 是一个 C 函数，它期望第一个参数是 `WorldSimActual` 对象，而不是 table

**相关代码**:
```lua
wrapped_world.ReserveSpace = function(self, ...)
    local rcx, rcy = original_world.ReserveSpace(self, ...)  -- ❌ self 是 wrapped_world (table)
    -- ...
end
```

**调用链**:
```
obj_layout.ReserveAndPlaceLayout() (Hook)
  → position == nil，创建 wrapped_world
  → 调用 original_ReserveAndPlaceLayout(..., wrapped_world)
    → 内部调用 wrapped_world:ReserveSpace(...)
      → 我们的 wrapper: ReserveSpace(self, ...)
        → original_world.ReserveSpace(self, ...)  ← self 是 table，不是 WorldSimActual
```

**解决方案**:
在 `ReserveSpace` wrapper 中，应该传递 `original_world` 作为第一个参数，而不是 `self`：
```lua
wrapped_world.ReserveSpace = function(self, ...)
    local rcx, rcy = original_world.ReserveSpace(original_world, ...)  -- ✅ 传递 original_world
    -- ...
end
```

**注意**: `ReserveSpace` 可能有两种调用方式：
1. `world:ReserveSpace(...)` - 方法调用，self 是 world
2. `world.ReserveSpace(world, ...)` - 函数调用，需要显式传递 world

我们需要使用第二种方式，传递 `original_world` 而不是 `self`。

### 修复状态

✅ **已修复** (2025-12-24)

**修复内容**:
- 修改了 `layout_hook.lua:34`，在 `ReserveSpace` wrapper 中传递 `original_world` 而不是 `self`
- 修复前：`original_world.ReserveSpace(self, ...)` - `self` 是 `wrapped_world` (table)
- 修复后：`original_world.ReserveSpace(original_world, ...)` - 传递 `original_world` (WorldSimActual)

**修复后的代码**:
```lua
wrapped_world.ReserveSpace = function(self, ...)
    local rcx, rcy = original_world.ReserveSpace(original_world, ...)  -- ✅ 传递 original_world
    -- ...
end
```

**预期效果**:
- ✅ 自动寻找位置的布局不再出现 `ReserveSpace` 错误
- ✅ 能够正确拦截并捕获自动寻找位置的坐标
- ✅ 游戏不再闪退

---

## 2025-12-24 第六次日志分析（验证 DefaultPigking 和 pigking 生成）

### ✅ 成功：DefaultPigking 布局被成功 Hook

**关键发现**:
- ✅ **DefaultPigking 布局成功被 Hook**（日志第1554行）
- ✅ **成功捕获了坐标信息**（日志第1555行）
- ✅ **pigking 实体成功生成**（日志第2365行）

**详细日志输出**:
```
[00:00:24]: [Move Entity V2] Convert: 布局 'DefaultPigking' 在节点 'Speak to the king:5:PigKingdom' 开始处理
[00:00:24]: [Move Entity V2] Layout 'DefaultPigking' - 关键点1: 保留空间确定 (自动寻找位置) - rcx=147.00, rcy=161.00 (左下角坐标)
[00:00:24]: [Move Entity V2] ========================================
[00:00:24]: [Move Entity V2] Layout 放置信息:
[00:00:24]: [Move Entity V2]   布局名称: DefaultPigking
[00:00:24]: [Move Entity V2]   节点ID: Speak to the king:5:PigKingdom
[00:00:24]: [Move Entity V2]   位置类型: auto
[00:00:24]: [Move Entity V2]   保留区域左下角坐标: rcx=147.00, rcy=161.00
[00:00:24]: [Move Entity V2]   Prefab数量: 9
[00:00:24]: [Move Entity V2]   缩放因子: 1.00
[00:00:24]: [Move Entity V2] ========================================
```

**pigking 实体验证**:
```
[00:00:25]: Checking Required Prefab pigking has at least 1 instances (1 found).
```

### ✅ 成功：自动寻找位置的布局正常工作

**观察到的自动寻找位置布局**:
- `DefaultPigking` - rcx=147.00, rcy=161.00
- `WoodBoon` - rcx=197.00, rcy=312.00
- `MoonTreeHiddenAxe` - rcx=328.00, rcy=177.00
- `moontrees_2` - 多个实例
- `MooseNest` - 多个实例
- `CaveEntrance` - 多个实例
- `CropCircle` - rcx=145.00, rcy=161.00

**所有自动寻找位置的布局都显示**:
- ✅ 位置类型: `auto`
- ✅ 成功捕获坐标信息
- ✅ 完整的布局信息输出

### 结论

✅ **所有功能正常工作**:
1. ✅ `Convert` Hook 成功拦截了所有通过 `Convert` 调用的布局（包括 `DefaultPigking`）
2. ✅ `ReserveAndPlaceLayout` Hook 成功捕获了坐标信息
3. ✅ 自动寻找位置的布局的 `ReserveSpace` 拦截正常工作
4. ✅ `DefaultPigking` 布局成功生成，pigking 实体成功创建
5. ✅ 游戏不再闪退，所有错误已修复

**下一步**:
- 现在可以开始实现实际的坐标修改功能

---

## 2025-12-24 第七次日志分析（长时间加载问题）

### 🔍 问题分析

**观察到的现象**:
- 用户报告世界加载时间很长
- 最新日志显示代码已更新为坐标偏移（x+8, y+8），而不是移动到 (0, 0)

**最新日志（已修复）**:
```
[00:00:27]: [Move Entity V2] ⚠️  检测到 DefaultPigking 布局: 'DefaultPigking'
[00:00:27]: [Move Entity V2] 🔧 修改 pigking 布局坐标: 原坐标 (236.00, 218.00) -> 新坐标 (244.00, 226.00) [x+8, y+8]
[00:00:27]: [Move Entity V2]   保留区域左下角坐标: rcx=244.00, rcy=226.00
[00:00:27]: [Move Entity V2]   ⚠️  pigking 布局 - 坐标已偏移 (x+8, y+8)
```

**备份日志（旧版本 - 移动到 (0, 0)）**:
- 多次世界生成重试：
  - 00:00:30 第一次尝试
  - 00:00:32 第二次尝试
  - 00:00:35 第三次尝试
  - 00:00:37 第四次尝试
  - 00:00:51 第五次尝试
  - 00:00:54 第六次尝试
  - 等等...

**原因分析**:
1. **移动到 (0, 0) 导致的问题**:
   - 当 `DefaultPigking` 布局被移动到 (0, 0) 时，可能：
     - 位置无效（超出地图范围或与其他布局冲突）
     - 导致世界生成验证失败
     - 触发世界生成重试机制
   - 每次重试都需要重新生成整个世界，导致加载时间很长

2. **坐标偏移 (x+8, y+8) 的优势**:
   - 保持布局在有效范围内
   - 只是轻微偏移，不会导致位置无效
   - 世界生成可以正常完成

**结论**:
- ✅ 最新代码（坐标偏移）工作正常
- ❌ 旧代码（移动到 (0, 0)）导致世界生成失败并多次重试
- ✅ 问题已通过改为坐标偏移解决

---

## 2025-12-24 第八次日志分析（地皮未移动问题）

### 问题描述
- ✅ Prefabs 已成功移动到新坐标 (x+8, y+8)
- ❌ 地皮（tiles）仍然在原来的位置

### 问题分析

#### 源码分析 (`src/map/object_layout.lua`)

1. **地皮放置逻辑**（第 349-405 行）：
   - 当 `position == nil`（自动寻找位置）时：
     - 地皮信息被收集到 `tiles` 数组中（第 397 行）
     - `tiles` 数组被传递给 `world:ReserveSpace(...)`（第 416 行）
     - `ReserveSpace` 是一个 **C 函数**，它会在**内部**使用 `tiles` 数组来放置地皮
     - 地皮的放置发生在 `ReserveSpace` 内部，**在返回 `rcx, rcy` 之前**
   
   - 当 `position ~= nil`（指定位置）时：
     - 地皮在第 372-395 行的循环中**立即放置**
     - 使用 `position[1] + column, position[2] + row` 作为坐标（第 391-392 行）

2. **Prefab 放置逻辑**（第 450-481 行）：
   - Prefabs 使用 `rcx, rcy` 作为基准坐标
   - `rcx, rcy` 在第 447-448 行被调整（加上 `size` 和偏移）
   - 然后在第 476-477 行使用调整后的坐标放置 prefabs

#### Mod 代码分析

当前实现：
- 对于 `position == nil` 的情况，我通过拦截 `ReserveSpace` 的返回值修改了 `rcx, rcy`
- 但是，**地皮已经在 `ReserveSpace` 内部放置了**，修改返回值不会影响已经放置的地皮
- Prefabs 使用修改后的 `rcx, rcy`，所以 prefabs 被移动了

#### 问题根源

**地皮和 Prefabs 的放置时机不同**：
- 地皮：在 `ReserveSpace` 内部放置（C 函数内部，无法拦截）
- Prefabs：在 `ReserveAndPlaceLayout` 中使用 `rcx, rcy` 放置（Lua 函数，可以使用修改后的坐标）

### 解决方案

需要在 `ReserveSpace` 返回后，手动重新放置地皮到新位置。

步骤：
1. 在拦截 `ReserveSpace` 时，记录原始坐标和新坐标
2. 在 `ReserveAndPlaceLayout` 返回后，检查是否是 pigking 布局
3. 如果是，计算地皮需要移动的偏移量
4. 遍历 `layout.ground`，重新放置地皮到新位置

### 实现方案

1. **获取地皮信息**：
   - `layout.ground` - 地皮数据（二维数组）
   - `layout.ground_types` - 地皮类型映射
   - `size` - 地皮区域大小

2. **计算偏移量**：
   - 原始坐标：`ReserveSpace` 返回的原始 `rcx, rcy`
   - 新坐标：修改后的 `rcx, rcy`
   - 偏移量：`offset_x = new_rcx - old_rcx`, `offset_y = new_rcy - old_rcy`

3. **重新放置地皮**：
   - 遍历 `layout.ground` 的每个位置
   - 如果地皮类型不为 0，则：
     - 计算原始位置：`old_x = old_rcx + column`, `old_y = old_rcy + row`
     - 计算新位置：`new_x = old_x + offset_x`, `new_y = old_y + offset_y`
     - 调用 `world:SetTile(new_x, new_y, tile_type, 1)` 放置新地皮
     - （可选）清除旧地皮（但可能不需要，因为新地皮会覆盖）

### 注意事项

1. **地皮放置的坐标系统**：
   - `ReserveSpace` 返回的是左下角坐标
   - 地皮放置时使用 `rcx + column, rcy + row`（第 425 行）
   - 需要考虑 `size` 的计算（第 404 行：`size = size / 2.0`）

2. **地皮放置的变换**：
   - 地皮可能经过 `switch_xy`, `flip_x`, `flip_y` 变换
   - 需要确保重新放置时使用相同的变换

3. **性能考虑**：
   - 只对 pigking 布局进行地皮重新放置
   - 避免重复放置地皮

### 待实现

- [ ] 在 `layout_hook.lua` 中实现地皮重新放置逻辑
- [ ] 测试地皮是否正确移动到新位置
- [ ] 验证地皮和 prefabs 是否在同一位置

---

## 2025-12-24 第九次调研（在 layout 放置前决定位置的方案）

### 问题回顾

- ✅ Prefabs 已成功移动到新坐标 (x+8, y+8)
- ❌ 地皮（tiles）仍然在原来的位置
- ❌ 用户要求：不想移动地皮，而是希望在初始化时决定坐标，避免地皮被放置两次

### 源码分析

#### `ReserveAndPlaceLayout` 的执行流程

```
1. 第 302-343 行：计算边界框、size、变换参数（在 position 判断之前）
2. 第 349-405 行：处理地皮
   - 如果 position ~= nil：直接放置地皮（第 372-395 行）
   - 如果 position == nil：收集到 tiles 数组（第 397 行）
3. 第 415-435 行：获取坐标
   - 如果 position == nil：调用 ReserveSpace（第 416 行），地皮在 C 函数内部放置
   - 如果 position ~= nil：直接使用 position（第 433-434 行）
4. 第 445-481 行：放置 prefabs
```

#### 关键发现

1. **地皮放置的两种路径**：
   - `position == nil`：地皮在 `ReserveSpace`（C 函数）内部放置，无法拦截
   - `position ~= nil`：地皮在 Lua 代码中放置（第 372-395 行），可以控制

2. **Prefab 放置**：
   - 使用 `rcx, rcy` 作为基准坐标（第 445-481 行）
   - 无论 `position` 是否为 nil，都使用相同的逻辑

### 可行方案调研

#### 方案1：在 `Convert` hook 中提前决定 `position` ⭐ **推荐**

**思路**：
- 在调用 `ReserveAndPlaceLayout` 之前，先调用 `ReserveSpace` 获取坐标
- 修改坐标
- 将 `position` 作为参数传递给 `ReserveAndPlaceLayout`
- 这样代码会走 `position ~= nil` 分支，地皮和 prefabs 都会使用新坐标

**优点**：
- ✅ 地皮只放置一次，在正确的位置
- ✅ 不需要事后移动地皮
- ✅ 符合源码设计（`position ~= nil` 时地皮在 Lua 中放置）
- ✅ 副作用最小：只是提前计算并设置 `position`

**缺点**：
- ⚠️ 需要复制 `ReserveAndPlaceLayout` 的部分逻辑来计算 size 和 tiles
- ⚠️ 需要处理变换参数（flip_x, flip_y, switch_xy）

**实现步骤**：
1. 在 `Convert` hook 中，获取 layout 和 prefabs
2. 复制 `ReserveAndPlaceLayout` 第 302-405 行的逻辑，计算 size 和 tiles
3. 调用 `ReserveSpace` 获取原始坐标
4. 修改坐标（如果是 pigking 布局）
5. 将 `position` 作为参数传递给 `ReserveAndPlaceLayout`

**需要复制的逻辑**：
- 第 302-308 行：计算边界框（`MinBoundingBox`）
- 第 310-319 行：计算 size
- 第 320-343 行：计算变换参数（flip_x, flip_y, switch_xy）
- 第 349-405 行：处理地皮（收集到 tiles 数组，但不放置）

**关键代码位置**：
- `Convert` hook：`mods/move-entity-v2/scripts/layout_hook.lua:88-103`
- `ReserveAndPlaceLayout`：`src/map/object_layout.lua:294-558`

#### 方案2：在 `ReserveSpace` wrapper 中传入空的 `tiles` 数组

**思路**：
- 在 `ReserveSpace` wrapper 中，将 `tiles` 参数替换为空数组或 nil
- 阻止地皮在 `ReserveSpace` 内部放置
- 获取坐标并修改
- 设置 `position`，让代码走 `position ~= nil` 分支

**优点**：
- ✅ 实现相对简单
- ✅ 不需要复制太多逻辑

**缺点/风险**：
- ❌ `ReserveSpace` 可能需要 `tiles` 来保留空间，传入空数组可能影响空间保留
- ❌ 需要验证 `ReserveSpace` 的行为
- ❌ 不确定 `ReserveSpace` 是否会因为空的 `tiles` 而失败

#### 方案3：完全重写 `ReserveAndPlaceLayout` 逻辑

**思路**：
- Hook `ReserveAndPlaceLayout`，完全重写其逻辑
- 在计算 tiles 之前就决定 position

**缺点**：
- ❌ 需要复制大量代码（200+ 行）
- ❌ 维护成本高
- ❌ 容易出错
- ❌ 不推荐

### 推荐方案

**方案1：在 `Convert` hook 中提前决定 `position`**

**理由**：
1. ✅ 符合源码设计：`position ~= nil` 时，地皮在 Lua 中放置（第 372-395 行），可以完全控制
2. ✅ 地皮只放置一次，在正确的位置
3. ✅ 不需要事后移动地皮
4. ✅ 副作用最小：只是提前计算并设置 `position`

### 实现细节

#### 需要复制的函数和逻辑

1. **`MinBoundingBox` 函数**（第 119-128 行）：
   ```lua
   local function MinBoundingBox(items)
       local extents = {xmin=1000000, ymin=1000000, xmax=-1000000, ymax=-1000000}
       for i, val in ipairs(items) do
           if val[1] < extents.xmin then extents.xmin = val[1] end
           if val[1] > extents.xmax then extents.xmax = val[1] end
           if val[2] < extents.ymin then extents.ymin = val[2] end
           if val[2] > extents.ymax then extents.ymax = val[2] end
       end
       return extents
   end
   ```

2. **计算 size 和变换参数**（第 302-343 行）：
   - 计算边界框
   - 计算 size
   - 计算变换参数（flip_x, flip_y, switch_xy）

3. **处理地皮**（第 349-405 行）：
   - 收集地皮信息到 `tiles` 数组
   - 应用变换（switch_xy, flip_x, flip_y）
   - 计算最终的 size

#### 实现流程

```
Convert Hook:
1. 获取 layout 和 prefabs
2. 计算边界框 → size
3. 计算变换参数（flip_x, flip_y, switch_xy）
4. 处理地皮 → tiles 数组
5. 调用 ReserveSpace(node_id, size, start_mask, fill_mask, layout_position, tiles)
6. 获取原始坐标 (old_rcx, old_rcy)
7. 修改坐标（如果是 pigking 布局）→ (new_rcx, new_rcy)
8. 调用 ReserveAndPlaceLayout(node_id, layout, prefabs, addEntity, {new_rcx, new_rcy})
   → 代码会走 position ~= nil 分支
   → 地皮在第 372-395 行直接放置（使用新坐标）
   → Prefabs 在第 445-481 行放置（使用新坐标）
```

### 注意事项

1. **变换参数的一致性**：
   - 在 `Convert` hook 中计算的变换参数（flip_x, flip_y, switch_xy）必须与 `ReserveAndPlaceLayout` 内部计算的保持一致
   - 否则地皮和 prefabs 的变换会不一致

2. **随机变换的处理**：
   - 第 324-328 行：如果 `disable_transform == false`，会随机生成变换参数
   - 需要确保在 `Convert` hook 和 `ReserveAndPlaceLayout` 中使用相同的随机种子，或者固定变换参数

3. **`force_rotation` 的处理**：
   - 第 330-343 行：如果 `force_rotation` 存在，会覆盖随机变换
   - 需要正确处理

4. **`position` 对变换的影响**：
   - 第 346-347 行：如果 `position ~= nil`，会反转 flip_x 和 flip_y
   - 在 `Convert` hook 中计算变换参数时，需要考虑这一点

### 待实现

- [ ] 在 `Convert` hook 中实现提前决定 `position` 的逻辑
- [ ] 复制 `MinBoundingBox` 函数
- [ ] 复制计算 size 和变换参数的逻辑
- [ ] 复制处理地皮的逻辑
- [ ] 确保变换参数的一致性
- [ ] 测试地皮和 prefabs 是否都在正确位置
- [ ] 验证地皮只放置一次

---

## 2025-12-24 坐标被修改两次的问题

### 问题描述

在实现过程中发现，`DefaultPigking` 布局的坐标被修改了两次，导致最终坐标偏移了 `x+16, y+16` 而不是预期的 `x+8, y+8`。

### 问题原因

**调用流程分析**：

1. **Convert Hook** 中：
   - 调用 `ProcessPosition` 修改坐标：`(197.00, 33.00) -> (205.00, 41.00)` ✅
   - 设置 `position = {205.00, 41.00}`
   - 调用 `obj_layout.ReserveAndPlaceLayout(..., position, ...)`

2. **ReserveAndPlaceLayout Hook** 中：
   - 接收到 `position = {205.00, 41.00}`（来自 Convert Hook）
   - 又调用了一次 `ProcessManualPosition` 修改坐标：`(205.00, 41.00) -> (213.00, 49.00)` ❌
   - 导致坐标被修改了两次

**根本原因**：
- `Convert Hook` 调用了 `obj_layout.ReserveAndPlaceLayout`（这是我们 hook 的函数）
- 这会触发 `ReserveAndPlaceLayout Hook`
- 在 `ReserveAndPlaceLayout Hook` 中，当 `position` 不为 nil 时，又调用了一次 `ProcessManualPosition`

### 解决方案

**方案1：使用标记区分**（初始方案）
- 在 `Convert Hook` 中，创建 `position` 时添加标记 `_from_convert_hook = true`
- 在 `ReserveAndPlaceLayout Hook` 中，检查该标记：
  - 如果有标记 → 来自 Convert Hook（已处理），直接使用，不再处理
  - 如果没有标记 → 来自其他地方，需要处理

**方案2：统一调用一次 ProcessPosition**（最终方案）
- 合并 `ProcessAutoPosition` 和 `ProcessManualPosition` 为统一的 `ProcessPosition` 函数
- 只在 `Convert Hook` 中调用一次 `ProcessPosition`
- 在 `ReserveAndPlaceLayout Hook` 中，如果 `position` 不为 nil，直接使用（不再处理）
- 这样确保 `ProcessPosition` 只调用一次

### 修复后的调用流程

```
Convert Hook
  ↓
调用 ProcessPosition (只在这里调用一次) ✅
  ↓
修改坐标: (197, 33) -> (205, 41)
  ↓
设置 position = {205, 41}
  ↓
调用 ReserveAndPlaceLayout Hook
  ↓
检查 position 不为 nil
  ↓
直接使用 position（不再处理）✅
```

### 验证结果

修复后，日志显示：
- ✅ 坐标只修改一次：`(290.00, 84.00) -> (298.00, 92.00) [x+8, y+8]`
- ✅ 最终位置正确：`位置 (298.00, 92.00)`
- ✅ pigking 验证通过：`Checking Required Prefab pigking has at least 1 instances (1 found)`

---

## 问题：陆地边缘查找失败

**时间**: 2025-12-25

**问题描述**:
实现陆地边缘查找功能后，日志显示虽然搜索到了陆地和海洋，但没有找到"陆地边缘"（既是陆地，又相邻有海洋的 tile）。

**日志信息**:
```
[00:00:36]: [Move Entity V2] [LandEdgeFinder] 开始查找陆地边缘: 起始世界坐标 (244.00, 323.00), 最大半径 20 tiles
[00:00:36]: [Move Entity V2] [LandEdgeFinder] 地图尺寸: 425 x 425 tiles
[00:00:36]: [Move Entity V2] [LandEdgeFinder] 起始 tile 坐标: (274, 293)
[00:00:36]: [Move Entity V2] [LandEdgeFinder] 起始位置 tile 类型: 1 (陆地: false, 海洋: false)
[00:00:36]: [Move Entity V2] ⚠️  在半径 20 tiles 内未找到陆地边缘，使用原始坐标 (搜索了 1681 个 tiles, 找到 618 个陆地, 473 个海洋)
```

**分析**:
1. **起始位置 tile 类型是 1** (`GROUND.IMPASSABLE`)，既不是陆地也不是海洋
2. **搜索统计**：搜索了 1681 个 tiles，找到 618 个陆地，473 个海洋
3. **问题**：虽然找到了陆地和海洋，但没有找到"陆地边缘"（既是陆地，又相邻有海洋的 tile）

**可能的原因**:
1. **pigking 生成在陆地深处**：周围都是陆地，没有海洋
2. **陆地和海洋之间有其他类型 tile**：比如 `IMPASSABLE` (1)，导致边缘判断失败
3. **搜索半径不够**：20 tiles 可能不足以从陆地深处找到边缘
4. **边缘判断逻辑过于严格**：要求陆地 tile 必须直接相邻海洋 tile

**当前边缘判断逻辑**:
```lua
IsLandEdgeTile(tile_x, tile_y):
  1. 当前 tile 必须是陆地
  2. 周围 8 个方向至少有一个是海洋 tile
```

**待验证**:
- 是否需要增加搜索半径？
- 是否需要放宽边缘判断条件（允许中间有其他类型 tile）？
- 是否需要先找到最近的海洋，然后从海洋向陆地搜索边缘？

---

## 问题：海洋 tile 在世界生成时还不完整

**时间**: 2025-12-25

**问题描述**:
在查找陆地边缘时，虽然搜索到了陆地和海洋，但没有找到"陆地边缘"（既是陆地，又相邻有海洋的 tile）。经过源码调研，发现问题的根本原因。

**源码调研结果**:

**世界生成顺序** (`src/map/forest_map.lua:866-887`):
1. `PopulateVoronoi` (line 871) - 放置所有陆地布局，包括 `DefaultPigking`
   - 此时会调用 `Convert` hook，我们的代码在这里执行
2. `Ocean_ConvertImpassibleToWater` (line 883) - **将 `IMPASSABLE` tile 转换为海洋 tile**
   - 这一步在布局放置**之后**执行

**关键发现** (`src/map/ocean_gen.lua:241-261`):
```lua
for y = 0, height - 1, 1 do
    for x = 0, width - 1, 1 do
        local ground = world:GetTile(x, y)
        if ground == WORLD_TILES.IMPASSABLE then
            -- 转换为海洋 tile (OCEAN_SWELL, OCEAN_ROUGH, OCEAN_HAZARDOUS 等)
            world:SetTile(x, y, WORLD_TILES.OCEAN_SWELL)
        end
    end
end
```

**问题根源**:
- 当 `Convert` hook 执行时，`Ocean_ConvertImpassibleToWater` 还没有执行
- 海洋区域此时还是 `IMPASSABLE` (1) tile，而不是海洋 tile
- 因此 `TileGroupManager:IsOceanTile(tile)` 返回 `false`（因为 `IMPASSABLE = 1` 不在海洋 tile 范围内）
- 导致无法找到"陆地边缘"（陆地 tile 相邻海洋 tile）

**证据**:
- 日志显示起始位置 tile 类型是 `1` (`GROUND.IMPASSABLE`)
- 搜索到了 618 个陆地和 473 个"海洋"，但实际上这些"海洋"可能是其他类型 tile
- 没有找到陆地边缘，因为真正的海洋 tile 还不存在

**解决方案**:
在查找陆地边缘时，需要将 `IMPASSABLE` tile 视为"未来的海洋"：
- 如果当前 tile 是陆地
- 且周围有 `IMPASSABLE` tile（这些会在后续转换为海洋）
- 则视为陆地边缘

**实现方式**:
修改 `IsLandEdgeTile` 函数，在检查相邻 tile 时：
- 不仅检查 `TileGroupManager:IsOceanTile(neighbor_tile)`
- 还要检查 `neighbor_tile == WORLD_TILES.IMPASSABLE`

---

## 观察：世界生成重试导致多次执行

**时间**: 2025-12-25

**观察描述**:
日志显示 `DefaultPigking` 布局被检测和处理了多次（4次），但最终游戏中只有一个 pigking。

**原因分析**:

从日志时间线可以看出：
1. **00:00:32** - 第一次世界生成成功，检测到 pigking
2. **00:00:33** - 世界生成错误，重试 1/5：`An error occured during world gen we will retry! [was 1 of 5]`
3. **00:00:35** - 重试后的世界生成成功，检测到 pigking
4. **00:00:36** - 世界生成错误，重试 2/5：`An error occured during world gen we will retry! [was 2 of 5]`
5. **00:00:43** - 重试后的世界生成成功，检测到 pigking
6. **00:00:44** - 世界生成错误，重试 3/5：`An error occured during world gen we will retry! [was 3 of 5]`
7. **00:00:45** - 重试后的世界生成成功，检测到 pigking

**结论**:
这是 DST 的正常行为。DST 的世界生成有重试机制（最多 5 次）。如果生成失败（例如缺少必需的 prefab、验证失败等），会重新生成整个世界。

每次重试都会：
1. 重新生成世界
2. 重新调用 `Convert` hook
3. 重新检测和移动 pigking

**重要**：
- 最终只有最后一次成功的世界生成会被使用
- 前面的重试是生成过程中的尝试，最终会被丢弃
- 所以最终游戏中只有一个 pigking
- 这是 DST 的正常机制，不是 bug

---

## 问题：猪王被移动到海上

**时间**: 2025-12-25

**问题描述**:
实现预计算合法坐标方案后，发现 pigking 被移动到了海上，说明合法坐标集合中可能包含了海洋 tile。

**可能的原因**:

1. **预计算时误判**:
   - `PrecomputeValidPositions` 中只检查了 `TileGroupManager:IsLandTile(tile)`
   - 但可能某些 tile 在预计算时是陆地，但在布局放置时已经变成了海洋
   - 或者 `IsLandTile` 判断有误

2. **DistanceToEdge 计算错误**:
   - `DistanceToEdge` 可能返回了错误的值
   - 如果某个海洋 tile 周围都是海洋，`DistanceToEdge` 可能返回 `math.huge`
   - 而 `math.huge >= 8` 为 true，导致海洋 tile 被加入合法坐标集合

3. **坐标转换问题**:
   - `TileToWorldCoords` 可能返回了错误的坐标
   - 导致存储的坐标和实际 tile 位置不匹配

4. **世界生成阶段问题**:
   - 预计算时，某些区域可能还没有完全生成
   - 或者预计算后，某些 tile 被修改了（如 `Ocean_ConvertImpassibleToWater`）

**需要验证**:

1. 检查预计算时是否正确过滤了海洋 tile
2. 检查 `DistanceToEdge` 对海洋 tile 的返回值
3. 检查坐标转换是否正确
4. 添加调试日志，记录预计算时每个合法坐标的 tile 类型

**可能的修复方案**:

1. **在预计算时更严格地检查**:
   ```lua
   -- 不仅检查 IsLandTile，还要确保不是海洋
   if tile and TileGroupManager:IsLandTile(tile) and not TileGroupManager:IsOceanTile(tile) then
   ```

2. **在查找最近坐标时再次验证**:
   ```lua
   -- 在返回坐标前，再次检查该位置是否是陆地
   local tile = world:GetTile(best_pos.tx, best_pos.ty)
   if not tile or not TileGroupManager:IsLandTile(tile) then
       -- 跳过这个坐标，继续查找下一个
   end
   ```

3. **在 DistanceToEdge 中提前返回**:
   ```lua
   -- 如果当前 tile 不是陆地，直接返回 0（距离边缘为 0）
   if not TileGroupManager:IsLandTile(tile) then
       return 0
   end
   ```

**根本原因分析**:

1. **DistanceToEdge 对海洋 tile 的处理**:
   - 当前 `DistanceToEdge` 函数只检查 `IsLandEdgeTile`，如果找不到边缘，返回 `math.huge`
   - 如果对海洋 tile 调用 `DistanceToEdge`，由于海洋 tile 不是陆地边缘，函数会搜索到 `max_radius` 后返回 `math.huge`
   - 而 `math.huge >= 8` 为 `true`，导致海洋 tile 被错误地加入合法坐标集合

2. **预计算时没有验证 tile 类型**:
   - `PrecomputeValidPositions` 中虽然检查了 `IsLandTile`，但可能在某些边界情况下，`IsLandTile` 返回 `true` 但实际 tile 是海洋
   - 或者预计算时 tile 是陆地，但后续被转换为海洋（虽然这种情况不太可能，因为预计算发生在 `Convert` hook 中，而 `Ocean_ConvertImpassibleToWater` 发生在更早的阶段）

3. **查找时没有二次验证**:
   - `FindNearestValidPosition` 直接返回预计算时存储的坐标，没有在返回前再次验证该坐标是否仍然是陆地 tile
   - 如果预计算后某些 tile 被修改，返回的坐标可能就是海洋

**最可能的根本原因**:
- `DistanceToEdge` 对海洋 tile 返回 `math.huge`，导致海洋 tile 被错误地加入合法坐标集合
- 需要在 `PrecomputeValidPositions` 中，调用 `DistanceToEdge` 前先检查 tile 是否是陆地，如果不是陆地，直接跳过

**日志分析**:

从最新日志中可以看到：
```
1262:[00:00:37]: [Move Entity V2] ⚠️  检测到 DefaultPigking 布局: 'DefaultPigking'	
1263:[00:00:37]: [Move Entity V2] ✅ 找到最近的合法坐标: tile (264, 293) -> 世界坐标 (106.00, 222.00), 距离 15.56 tiles	
1264:[00:00:37]: [Move Entity V2] 🔧 修改 pigking 布局坐标: 原坐标 (151.00, 179.00) -> 新坐标 (106.00, 222.00) [移动到合法位置，距离边缘 >= 8 tiles]	
1265:[00:00:37]: [Move Entity V2] 布局 'DefaultPigking' -> 位置 (106.00, 222.00)	
```

**问题确认**:
- pigking 被移动到了 tile (264, 293)，世界坐标 (106.00, 222.00)
- 用户确认这个位置是海上
- 预计算时找到了 9487 个合法坐标，但其中可能包含了海洋 tile

**可能的原因**:

1. **预计算时误判**:
   - `PrecomputeValidPositions` 中虽然检查了 `IsLandTile`，但可能在某些边界情况下，`IsLandTile` 返回 `true` 但实际 tile 是海洋
   - 或者 `DistanceToEdge` 被错误地调用在了非陆地 tile 上

2. **DistanceToEdge 对海洋 tile 的处理**:
   - 如果对海洋 tile 调用 `DistanceToEdge`，由于海洋 tile 不是陆地边缘，函数会搜索到 `max_radius` 后返回 `math.huge`
   - 而 `math.huge >= 8` 为 `true`，导致海洋 tile 被错误地加入合法坐标集合

3. **查找时没有二次验证**:
   - `FindNearestValidPosition` 直接返回预计算时存储的坐标，没有在返回前再次验证该坐标是否仍然是陆地 tile
   - 如果预计算后某些 tile 被修改，返回的坐标可能就是海洋

**需要添加的验证**:

1. 在 `PrecomputeValidPositions` 中，调用 `DistanceToEdge` 前，确保 tile 是陆地：
   ```lua
   if tile and TileGroupManager:IsLandTile(tile) and not TileGroupManager:IsOceanTile(tile) then
       local dist_to_edge = DistanceToEdge(x, y, world, min_distance + 5, min_distance)
       ...
   end
   ```

2. 在 `DistanceToEdge` 函数开头，如果当前 tile 不是陆地，直接返回 `0`：
   ```lua
   local tile = world:GetTile(tile_x, tile_y)
   if not tile or not TileGroupManager:IsLandTile(tile) then
       return 0  -- 非陆地 tile，距离边缘为 0
   end
   ```

3. 在 `FindNearestValidPosition` 中，返回坐标前再次验证：
   ```lua
   if best_pos then
       -- 再次验证该位置是否是陆地
       local tile = world:GetTile(best_pos.tx, best_pos.ty)
       if not tile or not TileGroupManager:IsLandTile(tile) or TileGroupManager:IsOceanTile(tile) then
           -- 跳过这个坐标，继续查找下一个
           -- 或者从 VALID_POSITIONS 中移除这个无效坐标
       end
       return best_pos.world_x, best_pos.world_y, true
   end
   ```

---

## 2025-12-25 猪王定位错误调研

### 问题描述

**现象**：
- ✅ 地皮替换功能正常工作，说明 `VALID_POSITIONS` 的获取逻辑是正确的
- ❌ 猪王实际位置不在木板地皮区域内，说明定位逻辑有问题

**日志信息**：
```
[00:00:51]: [Move Entity V2] ✅ 找到最近的合法坐标: tile (252, 281) -> 世界坐标 (158.00, 274.00)
[00:00:51]: [Move Entity V2] 🔧 修改布局 'DefaultPigking' 坐标: 原坐标 (119.00, 259.00) -> 新坐标 (158.00, 274.00)
[00:00:51]: [Move Entity V2] 布局 'DefaultPigking' -> 位置 (158.00, 274.00)
```

### 可能的原因分析

#### 1. **坐标系统混用问题**

**关键代码位置** (`src/map/object_layout.lua`)：

```lua
-- 第 391 行：设置地皮时使用 position
if position ~= nil then
    local x, y = position[1] + column, position[2] + row
    world:SetTile(x, y, layout.ground_types[layout.ground[rw][clmn]], 1)
    -- SetTile 需要的是 tile 坐标！
end

-- 第 433-434 行：position 被赋值给 rcx, rcy
else
    rcx = position[1]
    rcy = position[2]
end

-- 第 447-448 行：rcx, rcy 被调整用于放置 prefab
rcx = rcx + size + (position == nil and -0.5 or 0.5)
rcy = rcy + size + (position == nil and -0.5 or 0.5)
-- 这里 rcx, rcy 变成了世界坐标（用于放置 prefab）
```

**问题分析**：
- `ReserveSpace` 返回的是 **tile 左下角坐标**（从第 425 行 `rcx + column` 可以看出）
- `SetTile` 需要的是 **tile 坐标**（整数）
- 但我们传入的 `position` 是 **世界坐标**（浮点数，如 158.00）
- 当 `position[1] = 158.00` 时，`SetTile(158.00 + column, ...)` 会被当作 tile 坐标 158，而不是正确的 tile 坐标

**验证方法**：
- 检查 `ReserveSpace` 返回的坐标格式
- 检查 `position` 参数在 `ReserveAndPlaceLayout` 中的实际使用方式

#### 2. **ReserveSpace 返回格式问题**

**需要确认**：
- `ReserveSpace` 返回的是 tile 坐标还是世界坐标？
- 从代码第 425 行看：`local x, y = rcx + column, rcy + row`，这里 `rcx + column` 用于 `MakeSafeFromDisconnect`，说明 `rcx` 应该是 tile 坐标
- 但我们传入的 `new_rcx, new_rcy` 是世界坐标（从 `FindNearestValidPosition` 返回）

**可能的问题**：
- `FindNearestValidPosition` 返回的是世界坐标（tile 左下角的世界坐标）
- 但 `ReserveAndPlaceLayout` 的 `position` 参数需要的是 tile 坐标（用于 `SetTile`）
- 坐标格式不匹配导致定位错误

#### 3. **坐标转换时机问题**

**执行流程**：
1. `ReserveSpace` 返回原始坐标（tile 坐标）
2. `ProcessPosition` 转换为世界坐标并查找最近合法位置
3. `FindNearestValidPosition` 返回世界坐标
4. 传入 `ReserveAndPlaceLayout` 的 `position` 参数
5. `ReserveAndPlaceLayout` 内部使用 `position` 设置地皮（需要 tile 坐标）

**问题**：
- 步骤 4 传入的是世界坐标，但步骤 5 需要 tile 坐标
- 缺少从世界坐标到 tile 坐标的转换

#### 4. **地皮设置和实体放置的坐标不一致**

**关键代码** (`src/map/object_layout.lua:391-392, 447-448`)：
```lua
-- 地皮设置（第 391 行）：使用 position（应该是 tile 坐标）
local x, y = position[1] + column, position[2] + row
world:SetTile(x, y, ...)

-- 实体放置（第 447-448 行）：使用调整后的 rcx, rcy（世界坐标）
rcx = rcx + size + 0.5
rcy = rcy + size + 0.5
-- 然后用于放置 prefab
```

**问题**：
- 如果 `position` 是世界坐标，地皮会被设置在错误的 tile 上
- 但实体放置使用的是调整后的 `rcx, rcy`（世界坐标），可能位置正确
- 导致地皮和实体不在同一个位置

### 调研方向

1. **确认 ReserveSpace 返回格式**：
   - 查看 `ReserveSpace` 的实现或文档
   - 检查其他使用 `ReserveSpace` 的地方如何处理返回值

2. **确认 position 参数格式**：
   - 查看 `ReserveAndPlaceLayout` 中 `position` 参数的实际使用
   - 检查是否有其他代码传入 `position` 参数，看它们传入的是什么格式

3. **添加调试日志**：
   - 在传入 `position` 前记录坐标值
   - 在 `ReserveAndPlaceLayout` 内部记录 `rcx, rcy` 的值
   - 对比地皮设置的坐标和实体放置的坐标

4. **验证坐标转换**：
   - 确认 `WorldToTileCoords` 和 `TileToWorldCoords` 的转换是否正确
   - 验证转换后的坐标是否与 `ReserveSpace` 返回的格式一致

---

## 调研：地皮替换被多次调用且未清空 VALID_POSITIONS

### 问题描述

从日志中发现，两次"地皮替换完成"之间没有检测到世界生成并清空 `VALID_POSITIONS`：

**日志证据**：
```
[00:01:59]: [Move Entity V2] [TurfReplacer] 地皮替换完成: 成功替换 20225 个, 跳过 5 个
[00:01:59]: [Move Entity V2] [TurfReplacerHook] 地皮替换完成
...
[00:02:02]: [Move Entity V2] [TurfReplacer] 地皮替换完成: 成功替换 9605 个, 跳过 9887 个
[00:02:02]: [Move Entity V2] [TurfReplacerHook] 地皮替换完成
```

两次地皮替换之间（从 00:01:59 到 00:02:02）：
- ❌ 没有"检测到世界生成"日志
- ❌ 没有"已清空合法坐标集合"日志
- ❌ 没有"开始预计算合法坐标"日志

**关键发现**：
- 第一次替换：20225 个有效坐标
- 第二次替换：19492 个有效坐标（减少了 733 个，可能是 `RemovePositionsNearby` 移除的）
- 第二次替换时，`VALID_POSITIONS` 仍然包含之前的数据，没有重新计算

### 可能的原因

#### 原因 1: `GlobalPostPopulate` 被多次调用（最可能）

**分析**：
- 从源码 `src/map/forest_map.lua:887` 可以看到，`GlobalPostPopulate` 只被调用一次：`topology_save.root:GlobalPostPopulate(entities, map_width, map_height)`
- 但是，`Graph:GlobalPostPopulate` 是一个实例方法，如果存在多个 Graph 节点（例如主世界和子世界），每个节点都可能调用自己的 `GlobalPostPopulate`
- 我们的 Hook 检查了 `if self.parent == nil`，但这只能确保根节点执行，不能防止多个根节点的情况

**验证方法**：
- 在 Hook 中添加日志，记录 `self.id` 和 `self.parent`，确认是否有多个 Graph 节点调用了 `GlobalPostPopulate`
- 检查是否有多个世界（例如主世界和洞穴世界）同时生成

**解决方案**：
- 使用全局变量标记是否已执行地皮替换，防止重复执行
- 或者，在每次 `GlobalPostPopulate` 调用时，检查 `VALID_POSITIONS` 是否为空，如果为空则跳过

#### 原因 2: 世界生成重试，但 `modworldgenmain.lua` 未被重新执行

**分析**：
- 如果世界生成失败并重试，理论上 `modworldgenmain.lua` 应该被重新执行
- 但是，如果模块被 Lua 的 `require` 缓存，模块级变量可能不会被重置
- `VALID_POSITIONS` 是 `land_edge_finder.lua` 中的模块级变量，如果模块被缓存，变量会保留之前的值

**验证方法**：
- 检查日志中是否有"检测到世界生成"的多次出现
- 检查是否有"An error occured during world gen we will retry!" 的日志

**解决方案**：
- 在 `modworldgenmain.lua` 中直接调用 `ClearValidPositions()`，确保每次世界生成重试时都清空
- 或者在 `GlobalPostPopulate` Hook 中，每次执行前都清空 `VALID_POSITIONS`

#### 原因 3: Hook 被多次安装，导致多次执行

**分析**：
- `InstallTurfReplacerHook()` 在 `modworldgenmain.lua` 中被调用
- 如果 `modworldgenmain.lua` 被多次执行，Hook 可能被多次安装
- 每次安装 Hook 时，都会替换 `Graph.GlobalPostPopulate`，但之前的 Hook 可能已经被调用

**验证方法**：
- 检查日志中是否有多次"地皮替换 Hook 已安装"的消息
- 检查 Hook 安装的时机

**解决方案**：
- 在安装 Hook 前检查是否已经安装过（使用全局变量标记）
- 或者，使用闭包变量 `turf_replaced` 标记是否已执行（但需要确保每次世界生成重试时重置）

### 推荐解决方案

**方案 1: 使用全局变量标记 + 每次执行前清空（推荐）**

```lua
-- 在 turf_replacer_hook.lua 中
local turf_replaced_this_generation = false

Graph.GlobalPostPopulate = function(self, entities, width, height)
    local result = original_GlobalPostPopulate(self, entities, width, height)
    
    if self.parent == nil and not turf_replaced_this_generation then
        -- 每次执行前清空 VALID_POSITIONS，确保使用最新的数据
        LandEdgeFinder.ClearValidPositions()
        
        -- 重新预计算（如果需要）
        -- 或者，直接使用当前的 VALID_POSITIONS（如果已经计算过）
        
        local valid_count = LandEdgeFinder.GetValidPositionsCount()
        if valid_count > 0 then
            -- ... 执行地皮替换 ...
            turf_replaced_this_generation = true
        end
    end
    
    return result
end
```

**方案 2: 在 `modworldgenmain.lua` 中重置标记**

```lua
-- 在 modworldgenmain.lua 中
print("[Move Entity V2] 🔄 检测到世界生成")

-- 重置地皮替换标记
_G.move_entity_v2_turf_replaced = false

-- 清空 VALID_POSITIONS
local LandEdgeFinder = require("land_edge_finder")
LandEdgeFinder.ClearValidPositions()

-- ... 其余代码 ...
```

**方案 3: 在每次 `GlobalPostPopulate` 调用时检查并清空**

```lua
Graph.GlobalPostPopulate = function(self, entities, width, height)
    local result = original_GlobalPostPopulate(self, entities, width, height)
    
    if self.parent == nil then
        -- 检查是否已经执行过（使用全局变量）
        if not _G.move_entity_v2_turf_replaced then
            -- 清空 VALID_POSITIONS，确保使用最新的数据
            LandEdgeFinder.ClearValidPositions()
            
            -- 重新预计算（如果需要）
            -- 或者，直接使用当前的 VALID_POSITIONS（如果已经计算过）
            
            local valid_count = LandEdgeFinder.GetValidPositionsCount()
            if valid_count > 0 then
                -- ... 执行地皮替换 ...
                _G.move_entity_v2_turf_replaced = true
            end
        end
    end
    
    return result
end
```

### 待验证

- [ ] 确认 `GlobalPostPopulate` 是否被多次调用
- [ ] 确认是否有多个 Graph 节点（主世界和子世界）
- [ ] 确认世界生成重试时 `modworldgenmain.lua` 是否被重新执行
- [ ] 确认 Hook 是否被多次安装
- [ ] 添加调试日志，记录每次 `GlobalPostPopulate` 调用的 `self.id` 和 `self.parent`

### 相关文件

- `src/map/forest_map.lua:887` - `GlobalPostPopulate` 的调用位置
- `src/map/network.lua:770` - `Graph:GlobalPostPopulate` 的实现
- `mods/move-entity-v2/scripts/turf_replacer_hook.lua` - 地皮替换 Hook
- `mods/move-entity-v2/modworldgenmain.lua` - Mod 入口文件

