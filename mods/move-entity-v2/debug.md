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

