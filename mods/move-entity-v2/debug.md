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

