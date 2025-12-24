# Move Entity V2 Mod

## 项目概述
饥荒联机版实体移动 Mod

## 开发思路与方案

### 方案讨论记录

---

### 调研：PigKing 世界生成机制

**调研内容**: 了解 pigking 在世界生成时的创建流程，以及与其一起创建的 prefab

**关键发现**:

1. **静态布局文件**: `src/map/static_layouts/default_pigking.lua`
   - 定义了 pigking 及其周围环境的布局
   - FG_OBJECTS 层包含的 prefab:
     - `pigking` × 1 (中心位置: x=256, y=256)
     - `insanityrock` × 4 (疯狂石，分布在四周)
     - `sanityrock` × 4 (理智石，分布在四周)

2. **布局定义**: `src/map/layouts.lua`
   - `DefaultPigking` 布局引用静态布局文件
   - 使用 `StaticLayout.Get("map/static_layouts/default_pigking", {...})` 加载

3. **房间配置**: `src/map/rooms/forest/pigs.lua`
   - `PigKingdom` 房间使用 `DefaultPigking` 布局
   - 通过 `countstaticlayouts` 配置: `["DefaultPigking"]=1`

4. **创建流程**:
   - `StaticLayout.Get()` 解析布局文件，将 FG_OBJECTS 层对象转换为 prefab 列表
   - `Node:ConvertGround()` 在世界生成时调用 `object_layout.Convert()` 放置 prefab
   - 所有 prefab 在同一布局中按相对位置同时创建

**相关文件**:
- `src/map/static_layout.lua` - 静态布局解析器
- `src/map/object_layout.lua` - 布局到实体的转换
- `src/map/graphnode.lua` - 节点实体生成逻辑

---

### 调研：Layout 作为整体添加到世界的机制

**调研内容**: 了解一个 layout 是如何作为整体单元添加到世界中的

**关键发现**:

1. **整体放置流程** (`src/map/object_layout.lua`):
   ```
   Node:ConvertGround() 
   → obj_layout.Convert(node_id, layout_name, add_entity)
   → LayoutForDefinition() 获取布局定义
   → ConvertLayoutToEntitylist() 转换为 prefab 列表（相对坐标）
   → ReserveAndPlaceLayout() 执行整体放置
   ```

2. **ReserveAndPlaceLayout 核心步骤**:
   - **计算边界框**: 遍历所有 prefab 的相对坐标，计算最小边界框
   - **计算保留大小**: `size = max(width, height) * scale`
   - **应用变换**: 
     - 随机旋转/翻转（除非 `disable_transform = true`）
     - 支持 `force_rotation` 指定方向
     - 变换参数: `switch_xy`, `flip_x`, `flip_y`
   - **保留空间**: 
     - 调用 `world:ReserveSpace(node_id, size, start_mask, fill_mask, layout_position, tiles)`
     - 返回保留区域的左下角坐标 `(rcx, rcy)`
   - **放置 prefab**: 
     - 将保留区域左下角转换为中心点: `rcx = rcx + size - 0.5`
     - 对每个 prefab 的相对坐标应用变换
     - 转换为世界坐标: `world_x = rcx + relative_x * scale * flip_x`
     - 调用 `add_entity.fn()` 放置每个 prefab

3. **坐标系统**:
   - **布局文件**: 使用像素坐标 (Tiled 编辑器坐标)
   - **相对坐标**: 解析后转换为以布局中心为原点的相对坐标
   - **世界坐标**: 保留空间后，相对坐标 + 保留区域中心 = 世界坐标

4. **空间保留机制**:
   - `start_mask`: 搜索起始位置时的掩码（如 `PLACE_MASK.IGNORE_IMPASSABLE_BARREN_RESERVED`）
   - `fill_mask`: 填充区域时的掩码
   - `layout_position`: 布局位置偏好（如 `LAYOUT_POSITION.CENTER`）
   - `world:ReserveSpace()` 在节点内寻找合适位置，确保整个布局区域可用

5. **地形处理**:
   - 如果布局定义了 `ground` 层，会先设置地形瓦片
   - 地形数据也会应用相同的旋转/翻转变换
   - 地形设置和 prefab 放置在同一保留区域内完成

6. **关键特性**:
   - **原子性**: 整个布局要么全部放置成功，要么全部失败
   - **相对位置保持**: 布局内所有 prefab 的相对位置关系保持不变
   - **变换一致性**: 所有 prefab 和地形应用相同的变换（旋转/翻转）
   - **空间预留**: 先预留整个区域，避免与其他布局冲突

**相关代码位置**:
- `src/map/object_layout.lua:294` - `ReserveAndPlaceLayout()` 函数
- `src/map/object_layout.lua:509` - `Convert()` 函数
- `src/map/graphnode.lua:247` - `Node:ConvertGround()` 函数

---

### 方案：在布局放置前劫持并修改坐标

**目标**: 在布局放置前修改其坐标，实现布局的整体移动或调整

**可用的劫持点**:

#### 方案 1: Hook `object_layout.Convert` 函数
**位置**: `src/map/object_layout.lua:509`
**时机**: 在布局解析后、放置前
**优点**: 
- 可以在布局放置前进行拦截
- 可以结合方案2或方案3使用
- 可以针对特定布局名称进行条件判断
**实现**:
```lua
local obj_layout = require("map/object_layout")
local original_Convert = obj_layout.Convert
obj_layout.Convert = function(node_id, item, addEntity)
    -- 可以在这里判断是否需要移动特定布局
    if item == "DefaultPigking" then
        -- 结合方案2，Hook ReserveAndPlaceLayout 来修改位置
        -- 或者直接调用 ReserveAndPlaceLayout 并传入修改后的参数
    end
    
    return original_Convert(node_id, item, addEntity)
end
```

#### 方案 2: Hook `ReserveAndPlaceLayout` 函数
**位置**: `src/map/object_layout.lua:294`
**时机**: 在空间保留前（修改position）或空间保留后、prefab放置前（修改rcx/rcy）
**优点**:
- 可以直接修改 `position` 参数（整体移动布局，在保留空间前）
- 可以修改 `rcx, rcy`（保留区域的左下角坐标，在放置prefab前）
- 灵活性最高，可以针对不同布局进行不同处理
**执行顺序确认**:
```
ReserveAndPlaceLayout 流程：
1. 计算边界框和size (302-319行)
2. 应用变换 (320-343行)  
3. 处理地形tiles (349-405行)
4. 【保留空间】← 方案2在这里修改position (412-435行)
5. 【放置prefab】← 方案2在这里修改rcx/rcy (445-482行)
```

**实现（修改position参数 - 在保留空间前）**:
```lua
local obj_layout = require("map/object_layout")
local original_ReserveAndPlaceLayout = obj_layout.ReserveAndPlaceLayout
obj_layout.ReserveAndPlaceLayout = function(node_id, layout, prefabs, add_entity, position, world)
    -- ✅ 在保留空间前修改position（第415行判断前）
    -- 这会在第433-434行使用，在第481行放置prefab之前
    if position then
        position[1] = position[1] + offset_x
        position[2] = position[2] + offset_y
    end
    
    return original_ReserveAndPlaceLayout(node_id, layout, prefabs, add_entity, position, world)
end
```

**实现（修改rcx/rcy - 在放置prefab前）**:
```lua
local obj_layout = require("map/object_layout")
local original_ReserveAndPlaceLayout = obj_layout.ReserveAndPlaceLayout
obj_layout.ReserveAndPlaceLayout = function(node_id, layout, prefabs, add_entity, position, world)
    -- 修改position参数（如果提供）
    if position then
        position[1] = position[1] + offset_x
        position[2] = position[2] + offset_y
    end
    
    -- 对于自动寻找位置的布局，包装world:ReserveSpace来修改rcx/rcy
    -- ✅ 在第416行调用ReserveSpace时修改返回值，在第481行放置prefab之前
    if position == nil then
        local original_world = world or WorldSim
        local wrapped_world = setmetatable({}, {__index = original_world})
        wrapped_world.ReserveSpace = function(self, ...)
            local rcx, rcy = original_world.ReserveSpace(self, ...)
            if rcx then
                rcx = rcx + offset_x  -- 修改保留位置
                rcy = rcy + offset_y
            end
            return rcx, rcy
        end
        world = wrapped_world
    end
    
    return original_ReserveAndPlaceLayout(node_id, layout, prefabs, add_entity, position, world)
end
```

#### 方案 3: Hook `world:ReserveSpace` 返回值
**位置**: `ReserveAndPlaceLayout` 内部，第 416 行
**时机**: 空间保留时修改返回值，在放置prefab前（第481行之前）
**优点**:
- 最简单直接，适合整体平移布局
- 不影响相对坐标计算和边界框
- 适用于自动寻找位置的布局
**执行顺序确认**:
```
ReserveAndPlaceLayout 流程：
...
4. 【保留空间】world:ReserveSpace() ← 方案3在这里修改返回值 (416行)
5. 【放置prefab】add_entity.fn() ← 在第481行，方案3的修改已生效
```

**实现**:
```lua
-- 方法1: 直接 Hook WorldSim:ReserveSpace（影响所有布局）
local original_ReserveSpace = WorldSim.ReserveSpace
WorldSim.ReserveSpace = function(self, node_id, size, start_mask, fill_mask, layout_position, tiles)
    local rcx, rcy = original_ReserveSpace(self, node_id, size, start_mask, fill_mask, layout_position, tiles)
    -- ✅ 在第416行调用后立即修改，在第481行放置prefab之前生效
    if rcx and node_id == "目标节点ID" then  -- 可以添加条件判断
        rcx = rcx + offset_x  -- 修改保留位置
        rcy = rcy + offset_y
    end
    return rcx, rcy
end

-- 方法2: 在 Hook ReserveAndPlaceLayout 时包装 world 对象（更精确，只影响布局系统）
local obj_layout = require("map/object_layout")
local original_ReserveAndPlaceLayout = obj_layout.ReserveAndPlaceLayout
obj_layout.ReserveAndPlaceLayout = function(node_id, layout, prefabs, add_entity, position, world)
    if position == nil then  -- 只处理自动寻找位置的布局
        local original_world = world or WorldSim
        local wrapped_world = setmetatable({}, {__index = original_world})
        wrapped_world.ReserveSpace = function(self, ...)
            local rcx, rcy = original_world.ReserveSpace(self, ...)
            -- ✅ 在第416行调用时修改返回值，在第481行放置prefab之前生效
            if rcx then
                rcx = rcx + offset_x
                rcy = rcy + offset_y
            end
            return rcx, rcy
        end
        world = wrapped_world
    end
    return original_ReserveAndPlaceLayout(node_id, layout, prefabs, add_entity, position, world)
end
```

**方案对比**:

| 方案 | 修改层级 | 复杂度 | 灵活性 | 推荐度 |
|------|---------|--------|--------|--------|
| 方案1: Hook Convert | 中等 | 中 | 高 | ⭐⭐⭐⭐ |
| 方案2: Hook ReserveAndPlaceLayout | 低 | 中 | 高 | ⭐⭐⭐⭐⭐ |
| 方案3: Hook ReserveSpace 返回值 | 低 | 低 | 中 | ⭐⭐⭐⭐ |

**推荐方案**: 
- **方案2 (Hook ReserveAndPlaceLayout)** - 最灵活，可以同时修改位置和相对坐标，推荐用于复杂场景
- **方案3 (Hook ReserveSpace 返回值)** - 最简单，适合整体移动布局，推荐用于简单平移

**方案验证 - 确保在放置前修改**:

所有方案都在 `add_entity.fn()` 调用前（第481行）完成位置修改：

| 方案 | 修改时机 | 修改位置 | 是否在放置前 |
|------|---------|---------|------------|
| 方案2-修改position | 第415行判断前 | position参数 | ✅ 是（在第433-434行使用，第481行前） |
| 方案2-修改rcx/rcy | 第416行调用时 | ReserveSpace返回值 | ✅ 是（在第447-448行使用，第481行前） |
| 方案3 | 第416行调用时 | ReserveSpace返回值 | ✅ 是（在第447-448行使用，第481行前） |

**结论**: ✅ 所有方案都满足"在真正放置前修改位置"的要求

---

### 调研：Layout 真正放置位置在哪一步最终确定

**调研内容**: 分析 layout 放置位置的确定流程，找出位置最终确定的关键步骤

**关键发现**:

**完整的位置确定流程**:

```
ReserveAndPlaceLayout (src/map/object_layout.lua:294)
│
├─ 步骤1: 确定保留区域左下角坐标 (rcx, rcy)
│  ├─ 第416行: rcx, rcy = world:ReserveSpace(...)  [自动寻找位置]
│  └─ 第433-434行: rcx = position[1], rcy = position[2]  [指定位置]
│  └─ ✅ 【关键点1】布局整体位置的第一个确定点
│
├─ 步骤2: 转换为布局中心点坐标 (第447-448行)
│  ├─ rcx = rcx + size + offset
│  ├─ rcy = rcy + size + offset
│  └─ ✅ 【关键点2】布局中心位置的确定点
│
├─ 步骤3: 计算每个 prefab 的 tile 坐标 (第476-477行)
│  ├─ points_x = rcx + x * layout.scale
│  ├─ points_y = rcy + y * layout.scale
│  └─ ✅ 【关键点3】每个 prefab 的 tile 坐标确定点
│
├─ 步骤4: 调用 add_entity.fn() (第481行)
│  └─ 传入 tile 坐标: {points_x}, {points_y}
│
└─ PopulateWorld_AddEntity (src/map/graphnode.lua:188)
   ├─ 步骤5: 转换为世界坐标 (第193-194行)
   │  ├─ x = (tile_x - width/2.0) * TILE_SCALE
   │  ├─ y = (tile_y - height/2.0) * TILE_SCALE
   │  └─ ✅ 【关键点4】最终世界坐标的确定点
   │
   └─ 步骤6: 保存实体数据 (第208行)
      ├─ save_data = {x=x, z=y}
      └─ ✅ 【关键点5】实体数据的最终确定点（写入 savedata.ents）
```

**位置确定的5个关键点**:

| 关键点 | 代码位置 | 坐标类型 | 作用 | 可修改性 |
|--------|---------|---------|------|---------|
| **关键点1** | 第416行或433-434行 | tile坐标（左下角） | 确定布局整体位置 | ✅ 可修改（方案2/3） |
| **关键点2** | 第447-448行 | tile坐标（中心点） | 转换为布局中心 | ✅ 可修改（需深入Hook） |
| **关键点3** | 第476-477行 | tile坐标 | 计算每个prefab位置 | ✅ 可修改（需深入Hook） |
| **关键点4** | PopulateWorld_AddEntity:193-194 | 世界坐标 | 最终世界坐标 | ⚠️ 可修改但影响所有实体 |
| **关键点5** | PopulateWorld_AddEntity:208 | 保存数据 | 写入savedata | ❌ 不可修改（已确定） |

**结论**:

1. **布局整体位置的最终确定**: 
   - **第416行**（自动寻找位置）或 **第433-434行**（指定位置）
   - 此时 `rcx, rcy` 确定，代表布局保留区域的左下角坐标
   - **这是布局位置最关键的决定点**

2. **布局中心位置的确定**:
   - **第447-448行**，将左下角转换为中心点
   - 后续所有 prefab 的位置都基于这个中心点计算

3. **每个 prefab 位置的确定**:
   - **第476-477行**，基于布局中心 + 相对坐标计算
   - **PopulateWorld_AddEntity:193-194行**，转换为最终世界坐标

4. **实体数据的最终确定**:
   - **PopulateWorld_AddEntity:208行**，保存到 `entitiesOut[prefab]`
   - 此时位置已写入世界数据，无法再修改

**修改位置的最佳时机**:

- ✅ **推荐**: 在**关键点1**（第416行或433-434行）修改
  - 影响整个布局的位置
  - 所有后续计算都会基于修改后的位置
  - 实现简单，效果完整

- ⚠️ **不推荐**: 在**关键点4**（PopulateWorld_AddEntity）修改
  - 会影响所有通过此函数创建的实体
  - 可能破坏其他系统

**验证**: 方案2和方案3都在**关键点1**进行修改，确保在位置最终确定前完成修改。

**注意事项**:
1. 需要在 `modworldgenmain.lua` 中执行（世界生成阶段）
2. 需要确保在布局系统加载后、使用前进行 Hook
3. 方案2中修改 `position` 参数需要确保新位置有效且不冲突
4. 方案3修改 `rcx, rcy` 时需要注意坐标系统（左下角 vs 中心点）
5. 所有方案都保持布局内部相对位置关系不变，实现真正的整体移动
6. **关键**: 所有修改都在第481行 `add_entity.fn()` 调用前完成，确保实体在正确位置创建

---

### 深入理解：Layout 的定义和生成逻辑

**调研内容**: 深入理解 layout 的数据结构、定义方式、解析流程和生成机制

**关键发现**:

#### 1. Layout 的定义结构

Layout 有两种主要定义方式：

**方式1: 静态布局文件 (Static Layout File)**
- **文件位置**: `src/map/static_layouts/*.lua`
- **格式**: Tiled 地图编辑器导出的 Lua 格式
- **结构**:
  ```lua
  return {
    version = "1.1",
    luaversion = "5.1",
    orientation = "orthogonal",
    width = 32,        -- 地图宽度（单位：tile）
    height = 32,       -- 地图高度（单位：tile）
    tilewidth = 16,    -- 瓦片宽度（像素）
    tileheight = 16,   -- 瓦片高度（像素）
    layers = {
      {
        type = "tilelayer",
        name = "BG_TILES",  -- 背景地形层
        data = {0, 0, 6, ...}  -- 地形瓦片数据（一维数组）
      },
      {
        type = "objectgroup",
        name = "FG_OBJECTS",  -- 前景对象层
        objects = {
          {
            type = "pigking",  -- prefab 名称
            x = 256,           -- 像素坐标 X
            y = 256,           -- 像素坐标 Y
            width = 0,
            height = 0,
            properties = {}     -- 对象属性（可选）
          }
        }
      }
    }
  }
  ```

**方式2: 程序化布局定义 (Programmatic Layout)**
- **位置**: `src/map/layouts.lua` 等
- **结构**:
  ```lua
  {
    type = LAYOUT.STATIC,  -- 布局类型：STATIC, CIRCLE_EDGE, CIRCLE_RANDOM, GRID, RECTANGLE_EDGE
    layout = {            -- 静态布局：prefab -> 位置列表
      ["pigking"] = {
        {x = 0, y = 0},   -- 相对坐标（以布局中心为原点）
        {x = 1, y = 1}
      }
    },
    count = {             -- 动态布局：prefab -> 数量
      ["grass"] = 10
    },
    scale = 1.0,           -- 缩放因子
    defs = {               -- 定义替换（可选）
      ["unknown_plant"] = {"carrot_planted", "berrybush2"}
    },
    areas = {              -- 区域填充（可选）
      ["grass_area"] = function(area, data) return {"grass", "grass"} end
    },
    ground = {},           -- 地形数据（二维数组，ground[y][x]）
    ground_types = {},     -- 地形类型映射
    start_mask = 0,        -- 搜索起始位置掩码
    fill_mask = 0,         -- 填充区域掩码
    layout_position = 0,   -- 布局位置偏好
    disable_transform = false,  -- 禁用随机变换
    force_rotation = nil,  -- 强制旋转方向
    layout_file = "map/static_layouts/default_pigking"  -- 静态布局文件路径
  }
  ```

#### 2. Layout 的解析流程

**静态布局文件解析** (`src/map/static_layout.lua:27`):
```
ConvertStaticLayoutToLayout(layoutsrc, additionalProps)
1. require(layoutsrc) 加载静态布局文件
2. 解析 BG_TILES 层 → layout.ground (二维数组)
   - 支持 16x16 和 64x64 两种瓦片大小
   - tilefactor = ceil(64/tilewidth) 计算缩放因子
   - 将一维 data 数组转换为二维 ground[y][x]
3. 解析 FG_OBJECTS 层 → layout.layout
   - 遍历所有对象，提取 prefab 名称（obj.type）
   - 坐标转换：像素坐标 → 相对坐标（以布局中心为原点）
     * x = (obj.x + obj.width/2) / 64.0 - (width/tilefactor)/2
     * y = (obj.y + obj.height/2) / 64.0 - (height/tilefactor)/2
   - 解析对象属性（properties）并转换为嵌套表结构
   - 存储为 layout.layout[prefab] = {{x, y, properties, width, height}, ...}
4. 合并 additionalProps（如 start_mask, fill_mask 等）
5. 返回完整的 layout 对象
```

**布局定义查找** (`src/map/object_layout.lua:142`):
```
LayoutForDefinition(name, choices)
1. 在多个布局表中查找：
   - objs.Layouts (layouts.lua)
   - traps.Layouts (traps.lua)
   - pois.Layouts (pointsofinterest.lua)
   - protres.Layouts (protected_resources.lua)
   - boons.Layouts (boons.lua)
   - maze_rooms.Layouts (maze_layouts.lua)
2. 深拷贝找到的布局定义
3. 设置 layout.name = name
4. 返回 layout 对象
```

#### 3. Layout 到 Prefab 列表的转换

**ConvertLayoutToEntitylist** (`src/map/object_layout.lua:184`):
```
1. 处理 areas（区域填充）:
   - 如果 layout.areas 存在，遍历 layout.layout 中的区域对象
   - 调用 area 函数生成填充 prefab 列表
   - 将填充的 prefab 添加到 layout.layout 中

2. 处理 defs（定义替换）:
   - 如果 layout.defs 存在，随机选择替换项
   - 将 layout.layout 和 layout.count 中的占位符替换为实际 prefab

3. 应用布局函数:
   - 如果 layout.layout 存在，使用 StaticLayout 函数转换为位置列表
   - 如果 layout.type != STATIC，使用对应的布局函数（CircleEdge, Grid 等）
   - 合并所有位置，返回 prefabs 数组：
     [{prefab="pigking", x=0, y=0, properties={}}, ...]
```

#### 4. Layout 的放置流程

**完整流程**:
```
Node:ConvertGround() (graphnode.lua:247)
  ↓
obj_layout.Convert(node_id, "DefaultPigking", add_entity) (object_layout.lua:509)
  ↓
LayoutForDefinition("DefaultPigking") (object_layout.lua:142)
  - 查找 layouts.lua 中的定义
  - 如果是 StaticLayout.Get()，调用 ConvertStaticLayoutToLayout()
  - 返回 layout 对象
  ↓
ConvertLayoutToEntitylist(layout) (object_layout.lua:184)
  - 处理 areas 和 defs
  - 应用布局函数，转换为 prefabs 数组（相对坐标）
  ↓
ReserveAndPlaceLayout(node_id, layout, prefabs, add_entity) (object_layout.lua:294)
  - 计算边界框和 size
  - 应用变换（旋转/翻转）
  - 处理地形 tiles
  - 保留空间（world:ReserveSpace 或使用 position）
  - 放置所有 prefab（add_entity.fn）
```

#### 5. 坐标系统详解

**坐标转换链**:
```
1. Tiled 像素坐标 (静态布局文件)
   obj.x = 256, obj.y = 256
   ↓
2. 相对坐标（以布局中心为原点）
   x = (256 + 0) / 64.0 - (32/1)/2 = 0.0
   y = (256 + 0) / 64.0 - (32/1)/2 = 0.0
   ↓
3. 应用变换（旋转/翻转）
   x = x * flip_x
   y = y * flip_y
   if switch_xy then x, y = y, x end
   ↓
4. 世界坐标（保留空间后）
   world_x = rcx + x * layout.scale
   world_y = rcy + y * layout.scale
   (rcx, rcy 是保留区域中心点)
```

**关键坐标点**:
- **保留空间返回值** (`rcx, rcy`): 保留区域的左下角坐标（瓦片坐标）
- **中心点转换** (第447-448行): `rcx = rcx + size + offset`，转换为布局中心点
- **最终世界坐标** (第476-477行): `points_x = rcx + x * scale`

#### 6. Layout 的关键属性

| 属性 | 类型 | 说明 | 示例 |
|------|------|------|------|
| `type` | number | 布局类型（STATIC, CIRCLE_EDGE等） | `LAYOUT.STATIC` |
| `layout` | table | 静态布局：prefab -> 位置列表 | `{["pigking"]={{x=0,y=0}}}` |
| `count` | table | 动态布局：prefab -> 数量 | `{["grass"]=10}` |
| `scale` | number | 缩放因子 | `1.0` |
| `ground` | table | 地形数据（二维数组） | `ground[y][x]` |
| `start_mask` | number | 搜索起始位置掩码 | `PLACE_MASK.IGNORE_IMPASSABLE` |
| `fill_mask` | number | 填充区域掩码 | `PLACE_MASK.IGNORE_IMPASSABLE` |
| `layout_position` | number | 布局位置偏好 | `LAYOUT_POSITION.CENTER` |
| `disable_transform` | boolean | 禁用随机变换 | `false` |
| `force_rotation` | number | 强制旋转方向 | `LAYOUT_ROTATION.NORTH` |
| `layout_file` | string | 静态布局文件路径 | `"map/static_layouts/default_pigking"` |

#### 7. 示例：DefaultPigking 布局

**定义** (`src/map/layouts.lua:312`):
```lua
["DefaultPigking"] = StaticLayout.Get("map/static_layouts/default_pigking", {
    start_mask = PLACE_MASK.IGNORE_IMPASSABLE_BARREN_RESERVED,
    fill_mask = PLACE_MASK.IGNORE_IMPASSABLE_BARREN_RESERVED,
    layout_position = LAYOUT_POSITION.CENTER
})
```

**解析后的 layout 结构**:
```lua
{
    type = LAYOUT.STATIC,
    scale = 1,
    layout_file = "map/static_layouts/default_pigking",
    layout = {
        ["pigking"] = {{x=0, y=0, properties={}}},
        ["insanityrock"] = {
            {x=-2.5, y=-2.25, properties={}},
            {x=-3.5, y=0, properties={}},
            {x=2.5, y=0, properties={}},
            {x=0.0625, y=2.171875, properties={}}
        },
        ["sanityrock"] = {
            {x=1.140625, y=-0.0625, properties={}},
            {x=-1.171875, y=-0.203125, properties={}},
            {x=-1.171875, y=1.140625, properties={}},
            {x=1.109375, y=1.0625, properties={}}
        }
    },
    ground = {...},  -- 32x32 二维数组
    ground_types = {...},
    start_mask = PLACE_MASK.IGNORE_IMPASSABLE_BARREN_RESERVED,
    fill_mask = PLACE_MASK.IGNORE_IMPASSABLE_BARREN_RESERVED,
    layout_position = LAYOUT_POSITION.CENTER,
    name = "DefaultPigking"
}
```

**相关代码位置**:
- `src/map/static_layout.lua:27` - `ConvertStaticLayoutToLayout()` 静态布局解析
- `src/map/object_layout.lua:142` - `LayoutForDefinition()` 布局定义查找
- `src/map/object_layout.lua:184` - `ConvertLayoutToEntitylist()` 转换为 prefab 列表
- `src/map/layouts.lua:312` - `DefaultPigking` 布局定义

---

## 调研：移动到最近的陆地边缘 Tile

### 需求描述

将移动逻辑从简单的坐标偏移（x+8, y+8）改为：**移动到最近的、贴近陆地边缘的 tile 上**。

### 关键 API 调研

#### 1. Tile 坐标系统

- **TILE_SCALE**: `4.0`（定义在 `src/constants.lua:17`）
  - 每个 tile 的尺寸是 4x4 单位
  - 世界坐标和 tile 坐标的转换：`tile_coord = world_coord / TILE_SCALE`

#### 2. Map API（`TheWorld.Map` 或 `WorldSim`）

**坐标转换**:
- `Map:GetTileCoordsAtPoint(x, y, z)` → 返回 `(tx, ty)` tile 坐标
- `Map:GetTileCenterPoint(tx, ty)` → 返回 `(cx, cy, cz)` tile 中心点的世界坐标

**Tile 查询**:
- `Map:GetTileAtPoint(x, y, z)` → 返回世界坐标点的 tile 类型（数字）
- `Map:GetTile(tx, ty)` → 返回 tile 坐标的 tile 类型（数字）

**Tile 类型检查**:
- `Map:IsLandTileAtPoint(x, y, z)` → 检查世界坐标点是否是陆地 tile
- `Map:IsOceanTileAtPoint(x, y, z)` → 检查世界坐标点是否是海洋 tile

#### 3. TileGroupManager API

- `TileGroupManager:IsLandTile(tile)` → 检查 tile 类型是否是陆地
- `TileGroupManager:IsOceanTile(tile)` → 检查 tile 类型是否是海洋

**相关代码位置**:
- `src/components/map.lua:75-93` - Map tile 检查函数
- `src/tilegroups.lua` - TileGroupManager 定义

### 陆地边缘的定义

**陆地边缘 tile** 需要满足以下条件：
1. 该 tile 本身是**陆地 tile**（`TileGroupManager:IsLandTile(tile) == true`）
2. 该 tile 的**周围 8 个方向**（上、下、左、右、左上、右上、左下、右下）中，**至少有一个是海洋 tile**

**8 个方向的偏移**:
```lua
local directions = {
    {0, 1},   -- 上
    {0, -1},  -- 下
    {-1, 0},  -- 左
    {1, 0},   -- 右
    {-1, 1},  -- 左上
    {1, 1},   -- 右上
    {-1, -1}, -- 左下
    {1, -1}   -- 右下
}
```

### 搜索策略

#### 方案 1: 螺旋搜索（推荐）

从原始坐标开始，以螺旋方式向外搜索：

```lua
function FindNearestLandEdgeTile(start_x, start_y, max_radius)
    local map = WorldSim  -- 或 TheWorld.Map（取决于世界生成阶段）
    local start_tx, start_ty = map:GetTileCoordsAtPoint(start_x, 0, start_y)
    
    -- 螺旋搜索：从内到外，逐层搜索
    for radius = 0, max_radius do
        for dx = -radius, radius do
            for dy = -radius, radius do
                -- 只检查当前层的边界 tile（避免重复检查内层）
                if math.abs(dx) == radius or math.abs(dy) == radius then
                    local tx, ty = start_tx + dx, start_ty + dy
                    local tile = map:GetTile(tx, ty)
                    
                    if TileGroupManager:IsLandTile(tile) then
                        -- 检查是否是陆地边缘
                        if IsLandEdgeTile(map, tx, ty) then
                            local cx, _, cy = map:GetTileCenterPoint(tx, ty)
                            return cx, cy  -- 返回 tile 中心点的世界坐标
                        end
                    end
                end
            end
        end
    end
    
    return nil, nil  -- 未找到
end

function IsLandEdgeTile(map, tx, ty)
    local directions = {
        {0, 1}, {0, -1}, {-1, 0}, {1, 0},
        {-1, 1}, {1, 1}, {-1, -1}, {1, -1}
    }
    
    for _, dir in ipairs(directions) do
        local neighbor_tile = map:GetTile(tx + dir[1], ty + dir[2])
        if TileGroupManager:IsOceanTile(neighbor_tile) then
            return true  -- 找到相邻的海洋 tile，说明是陆地边缘
        end
    end
    
    return false
end
```

#### 方案 2: 同心圆搜索

按距离从近到远搜索，使用距离平方避免开方计算：

```lua
function FindNearestLandEdgeTile(start_x, start_y, max_radius)
    local map = WorldSim
    local start_tx, start_ty = map:GetTileCoordsAtPoint(start_x, 0, start_y)
    local candidates = {}
    
    -- 收集所有陆地边缘 tile
    for dx = -max_radius, max_radius do
        for dy = -max_radius, max_radius do
            local dist_sq = dx * dx + dy * dy
            local tx, ty = start_tx + dx, start_ty + dy
            local tile = map:GetTile(tx, ty)
            
            if TileGroupManager:IsLandTile(tile) and IsLandEdgeTile(map, tx, ty) then
                table.insert(candidates, {tx = tx, ty = ty, dist_sq = dist_sq})
            end
        end
    end
    
    -- 按距离排序，返回最近的
    if #candidates > 0 then
        table.sort(candidates, function(a, b) return a.dist_sq < b.dist_sq end)
        local best = candidates[1]
        local cx, _, cy = map:GetTileCenterPoint(best.tx, best.ty)
        return cx, cy
    end
    
    return nil, nil
end
```

### 注意事项

1. **坐标对齐约束**（重要）:
   - **移动前后的 delta x 和 delta y 必须是 4 的倍数**（1 tile 的倍数）
   - 因为 `TILE_SCALE = 4`，坐标必须是 tile 对齐的
   - 这意味着：
     - 原始坐标：`(rcx, rcy)` - 来自 `ReserveSpace` 返回
     - 目标坐标：`(new_rcx, new_rcy)` - 找到的陆地边缘 tile 的中心点
     - **约束**：`(new_rcx - rcx) % 4 == 0` 且 `(new_rcy - rcy) % 4 == 0`
   - **实现方式**：
     - 使用 `GetTileCenterPoint(tx, ty)` 获取 tile 中心点（已经是 tile 对齐的）
     - 或者将坐标对齐到最近的 tile 边界：`aligned_x = math.floor(x / 4) * 4 + 2`（中心点）
     - 确保最终坐标是 tile 对齐的，避免布局放置时出现偏移

2. **世界生成阶段**:
   - 在世界生成阶段，应使用 `WorldSim` 而不是 `TheWorld.Map`
   - `WorldSim` 是 C++ 对象，需要通过 `WorldSim:GetTile(tx, ty)` 访问
   - 需要确认 `WorldSim` 是否有 `GetTileCoordsAtPoint` 和 `GetTileCenterPoint` 方法

3. **性能考虑**:
   - 搜索范围 `max_radius` 需要合理设置（建议 10-20 tiles）
   - 螺旋搜索比同心圆搜索更高效（找到第一个就返回）
   - 如果找不到陆地边缘，可以回退到原始坐标或使用简单的偏移

4. **边界检查**:
   - 需要检查 tile 坐标是否在世界范围内
   - 避免访问无效的 tile 坐标

5. **坐标系统**:
   - `ReserveSpace` 返回的坐标是**世界坐标**（左下角）
   - 需要转换为 tile 坐标进行搜索
   - 找到目标 tile 后，需要转换回世界坐标（使用 tile 中心点）
   - **重要**：确保最终坐标是 tile 对齐的（4 的倍数）

### 实现建议

1. **创建新模块**: `scripts/land_edge_finder.lua`
   - 封装 `FindNearestLandEdgeTile` 函数
   - 封装 `IsLandEdgeTile` 函数
   - 处理坐标转换

2. **修改 `pigking_handler.lua`**:
   - 将 `ProcessPosition` 中的简单偏移逻辑改为调用 `FindNearestLandEdgeTile`
   - 如果找不到陆地边缘，可以回退到原始坐标或简单偏移

3. **测试**:
   - 测试不同地形情况（完全陆地、完全海洋、混合地形）
   - 测试边界情况（找不到陆地边缘、超出搜索范围）

---

## 调研：确保距离边缘的最小距离不少于 8 tiles

**时间**: 2025-12-25

**需求描述**:
修改移动逻辑，不再是移动到边缘，而是确保 pigking 布局距离边缘的最小距离不少于 8 tiles (32 units)。如果当前位置距离边缘小于 8 tiles，则移动到符合条件的最近位置。

**关键约束**:
1. **最小距离**: 距离边缘至少 8 tiles (32 units)
2. **移动目标**: 如果当前位置不符合要求，移动到符合条件的最近位置
3. **坐标对齐**: 移动前后的 delta x 和 delta y 必须是 4 的倍数（TILE_SCALE）

**实现方案分析**:

### 方案1：从边缘向陆地内部移动（推荐）

**思路**:
1. 找到最近的陆地边缘 tile（使用现有的 `FindNearestLandEdgeTile`）
2. 计算当前位置到边缘的距离
3. 如果距离 < 8 tiles：
   - 从边缘位置向陆地内部移动至少 8 tiles
   - 找到第一个距离边缘 >= 8 tiles 的陆地 tile
4. 如果距离 >= 8 tiles：
   - 保持当前位置不变

**优点**:
- 逻辑清晰，易于实现
- 可以复用现有的边缘查找逻辑
- 移动方向明确（从边缘向陆地内部）

**缺点**:
- 如果当前位置已经在陆地深处，可能需要移动较远距离
- 需要确定"向陆地内部"的方向

### 方案2：从当前位置向陆地内部搜索

**思路**:
1. 检查当前位置距离边缘的距离
2. 如果距离 < 8 tiles：
   - 从当前位置开始，向陆地内部方向搜索
   - 找到第一个距离边缘 >= 8 tiles 的陆地 tile
3. 如果距离 >= 8 tiles：
   - 保持当前位置不变

**优点**:
- 如果当前位置已经符合要求，不需要移动
- 移动距离可能更短

**缺点**:
- 需要确定"向陆地内部"的方向
- 如果当前位置在边缘附近，可能找不到符合条件的 tile

### 推荐实现步骤（方案1）:

1. **找到最近的边缘**:
   ```lua
   local edge_world_x, edge_world_y, found = FindNearestLandEdgeTile(world_x, world_y, world, max_radius)
   ```

2. **计算当前位置到边缘的距离**:
   ```lua
   local start_tx, start_ty = WorldToTileCoords(world_x, world_y, map_width, map_height)
   local edge_tx, edge_ty = WorldToTileCoords(edge_world_x, edge_world_y, map_width, map_height)
   local dist_to_edge = math.sqrt((start_tx - edge_tx)^2 + (start_ty - edge_ty)^2)
   ```

3. **如果距离 < 8 tiles，从边缘向陆地内部移动**:
   - 计算从边缘到当前位置的方向向量（归一化）
   - 从边缘位置开始，沿着这个方向向陆地内部移动至少 8 tiles
   - 搜索符合条件的陆地 tile（距离边缘 >= 8 tiles）

4. **如果距离 >= 8 tiles，保持当前位置不变**

**关键实现细节**:

1. **方向计算**:
   ```lua
   local dx = start_tx - edge_tx
   local dy = start_ty - edge_ty
   local dist = math.sqrt(dx^2 + dy^2)
   if dist > 0 then
       local dir_x = dx / dist  -- 归一化方向向量
       local dir_y = dy / dist
   else
       -- 当前位置就是边缘，需要选择一个向陆地内部的方向
       -- 可以搜索周围 8 个方向，找到第一个陆地 tile 的方向
   end
   ```

2. **从边缘向陆地内部移动**:
   ```lua
   -- 从边缘位置开始，沿着方向向量移动至少 8 tiles
   for step = 8, max_search_distance do
       local tx = edge_tx + math.floor(dir_x * step)
       local ty = edge_ty + math.floor(dir_y * step)
       
       -- 检查是否是陆地 tile
       local tile = world:GetTile(tx, ty)
       if tile and TileGroupManager:IsLandTile(tile) then
           -- 检查距离边缘是否 >= 8 tiles
           if DistanceToEdge(tx, ty, world) >= 8 then
               return TileToWorldCoords(tx, ty, map_width, map_height)  -- 找到符合条件的 tile
           end
       end
   end
   ```

3. **距离边缘的计算**:
   ```lua
   -- 检查一个 tile 距离边缘的距离（使用螺旋搜索）
   function DistanceToEdge(tile_x, tile_y, world, max_radius)
       max_radius = max_radius or 20
       for radius = 0, max_radius do
           for dx = -radius, radius do
               for dy = -radius, radius do
                   if math.abs(dx) == radius or math.abs(dy) == radius then
                       local tx, ty = tile_x + dx, tile_y + dy
                       if IsLandEdgeTile(world, tx, ty) then
                           return radius  -- 返回距离（tile 单位）
                       end
                   end
               end
           end
       end
       return math.huge  -- 未找到边缘
   end
   ```

**注意事项**:

1. **坐标对齐**:
   - 最终坐标必须是 tile 对齐的（4 的倍数）
   - 使用 `TileToWorldCoords` 转换时，返回的是 tile 左下角坐标
   - 确保移动距离是 4 的倍数

2. **边界检查**:
   - 需要检查 tile 坐标是否在世界范围内
   - 避免访问无效的 tile 坐标

3. **性能考虑**:
   - 距离边缘的计算可能需要搜索较大范围（最多 20 tiles）
   - 可以考虑限制搜索范围，或者使用近似算法

4. **回退策略**:
   - 如果找不到符合条件的 tile（距离边缘 >= 8 tiles），可以：
     - 使用找到的距离边缘最远的 tile
     - 或者使用原始坐标

5. **特殊情况处理**:
   - 如果当前位置就是边缘（距离 = 0），需要选择一个向陆地内部的方向
   - 可以搜索周围 8 个方向，找到第一个陆地 tile 的方向

**实现建议**:

1. **修改 `LandEdgeFinder`**:
   - 添加 `FindPositionWithMinDistanceFromEdge` 函数
   - 添加 `DistanceToEdge` 辅助函数
   - 复用现有的 `FindNearestLandEdgeTile` 和 `IsLandEdgeTile` 函数

2. **修改 `PigkingHandler`**:
   - 将 `ProcessPosition` 中的逻辑改为调用 `FindPositionWithMinDistanceFromEdge`
   - 最小距离参数设置为 8 tiles

3. **测试**:
   - 测试当前位置距离边缘 < 8 tiles 的情况
   - 测试当前位置距离边缘 >= 8 tiles 的情况（应该不移动）
   - 测试边界情况（找不到符合条件的 tile、当前位置就是边缘）

### 方案3：预计算合法坐标集合（用户提供）

**思路**:
1. 设置一个全局变量保存世界 map 的所有合法坐标（距离边缘 >= 8 tiles 的陆地 tile）
2. 在世界生成时，预先计算并存储所有符合条件的坐标
3. 在检查坐标时，从合法坐标集合中寻找距离当前位置最近的坐标并移动

**优点**:
- 性能好：只需要一次预计算，后续查找是 O(n) 或 O(log n)
- 逻辑简单：只需要在合法坐标集合中找最近的点
- 可以处理复杂地形：预先筛选出所有符合条件的坐标

**缺点**:
- 需要存储大量坐标（可能几千个 tile）
- 需要确定何时进行预计算（世界生成阶段）
- 如果世界生成失败重试，需要重新计算

**实现步骤**:

1. **预计算合法坐标集合**:
   ```lua
   -- 全局变量
   local VALID_POSITIONS = {}  -- 存储所有距离边缘 >= 8 tiles 的坐标
   
   -- 在世界生成时调用
   function PrecomputeValidPositions(world, map_width, map_height, min_distance)
       min_distance = min_distance or 8  -- 最小距离（tile 单位）
       VALID_POSITIONS = {}
       
       -- 遍历所有陆地 tile
       for y = 0, map_height - 1 do
           for x = 0, map_width - 1 do
               local tile = world:GetTile(x, y)
               if tile and TileGroupManager:IsLandTile(tile) then
                   -- 检查距离边缘是否 >= min_distance
                   local dist_to_edge = DistanceToEdge(x, y, world, min_distance + 5)
                   if dist_to_edge >= min_distance then
                       -- 转换为世界坐标并存储
                       local world_x, world_y = TileToWorldCoords(x, y, map_width, map_height)
                       table.insert(VALID_POSITIONS, {
                           tx = x,
                           ty = y,
                           world_x = world_x,
                           world_y = world_y
                       })
                   end
               end
           end
       end
       
       print(string.format("[Move Entity V2] 预计算完成，找到 %d 个合法坐标", #VALID_POSITIONS))
   end
   ```

2. **查找最近的合法坐标**:
   ```lua
   function FindNearestValidPosition(world_x, world_y, map_width, map_height)
       if #VALID_POSITIONS == 0 then
           -- 如果还没有预计算，返回原始坐标
           return world_x, world_y, false
       end
       
       local start_tx, start_ty = WorldToTileCoords(world_x, world_y, map_width, map_height)
       local min_dist_sq = math.huge
       local best_pos = nil
       
       -- 遍历所有合法坐标，找到最近的
       for _, pos in ipairs(VALID_POSITIONS) do
           local dx = pos.tx - start_tx
           local dy = pos.ty - start_ty
           local dist_sq = dx * dx + dy * dy
           
           if dist_sq < min_dist_sq then
               min_dist_sq = dist_sq
               best_pos = pos
           end
       end
       
       if best_pos then
           return best_pos.world_x, best_pos.world_y, true
       else
           return world_x, world_y, false
       end
   end
   ```

3. **优化：使用空间索引**:
   - 可以使用网格索引或四叉树来加速查找
   - 或者按区域分组，只搜索附近的区域

**关键实现细节**:

1. **预计算时机**:
   - 可以在 `modworldgenmain.lua` 中，在布局放置之前进行预计算
   - 或者使用 `AddSimPostInit` 在世界生成完成后计算（但此时可能已经太晚了）

2. **存储格式**:
   ```lua
   VALID_POSITIONS = {
       {tx = 100, ty = 150, world_x = 200.0, world_y = 300.0},
       {tx = 101, ty = 150, world_x = 204.0, world_y = 300.0},
       -- ...
   }
   ```

3. **性能优化**:
   - 可以只存储 tile 坐标，需要时再转换为世界坐标
   - 可以使用哈希表按区域索引，加速查找
   - 可以限制搜索范围（只搜索附近的合法坐标）

4. **边界情况**:
   - 如果预计算时还没有找到合法坐标，可以回退到原始坐标
   - 如果合法坐标集合为空，说明地图太小或地形特殊

**实现建议**:

1. **在 `LandEdgeFinder` 中添加**:
   - `PrecomputeValidPositions` 函数
   - `FindNearestValidPosition` 函数
   - 全局变量 `VALID_POSITIONS`

2. **在 `modworldgenmain.lua` 中调用**:
   ```lua
   local LandEdgeFinder = require("land_edge_finder")
   LandEdgeFinder.PrecomputeValidPositions(WorldSim, map_width, map_height, 8)
   ```

3. **修改 `PigkingHandler`**:
   - 将 `ProcessPosition` 中的逻辑改为调用 `FindNearestValidPosition`

**注意事项**:

1. **预计算时机**:
   - 需要确保在世界生成阶段，所有 tile 都已经生成
   - 需要在布局放置之前完成预计算

2. **内存占用**:
   - 合法坐标可能很多（几千个），但每个坐标只存储几个数字，内存占用不大

3. **世界生成重试**:
   - 如果世界生成失败重试，需要重新计算合法坐标集合
   - 可以在每次世界生成开始时清空并重新计算

---

## 调研：扩展移动逻辑到其他 Layout

**需求**: 除了 `DefaultPigking` 之外，还需要对以下 layout 应用相同的移动逻辑（移动到距离边缘至少 8 tiles 的位置）。

**重要区分**: Layout vs Prefab vs Room
- **Layout**: 在 `src/map/layouts.lua` 中定义的静态布局，通过 `object_layout.Convert` 放置
- **Prefab**: 游戏中的实体对象（如 `dragonfly_spawner`、`beequeenhive` 等）
- **Room**: 在世界生成时定义的区域，可能使用 `countprefabs` 直接放置 prefab，或使用 `countstaticlayouts` 放置 layout

### Layout 名称调研

通过阅读源码 (`src/map/layouts.lua` 和相关文件)，确认了以下内容：

#### 1. **BeeQueen (蜜蜂女王)**
- **类型**: Prefab (`beequeenhive`)
- **放置方式**: 通过 Room `BeeQueenBee` 的 `countprefabs` 直接放置
- **位置**: `src/map/rooms/forest/bee.lua:19`
- **说明**: 不是 layout，是 room 直接放置的 prefab
- **结论**: ❌ **无法通过 hook layout 处理**，需要 hook room 的 prefab 放置机制（更复杂）

#### 2. **Dragonfly (龙蝇)**
- **类型**: Layout + Prefab
- **Layout 名称**: `DragonflyArena`
- **Prefab 名称**: `dragonfly_spawner`
- **定义位置**: `src/map/layouts.lua:899`
- **说明**: `DragonflyArena` layout 包含 `dragonfly_spawner` prefab（在 `dragonfly_arena.lua:157` 中定义）
- **状态**: ✅ **可以通过 hook layout 处理**

#### 3. **Moon Stage (月亮舞台)**
- **类型**: Layout + Prefab
- **Layout 名称**: `MoonbaseOne`
- **Prefab 名称**: `moonbase` (月亮设备)
- **定义位置**: `src/map/layouts.lua:936`
- **说明**: 月亮基地 layout，包含 `moonbase` prefab
- **状态**: ✅ **可以通过 hook layout 处理**
- **注意**: 用户提到的 "moonstage" 可能指的是这个 layout

#### 4. **Charlie Stage (查理舞台)**
- **类型**: Layout + Prefab
- **Layout 名称**: `Charlie1` 和 `Charlie2`
- **Prefab 名称**: `charlie_stage_post`
- **定义位置**: `src/map/layouts.lua:439-440`
- **说明**: 两个 layout 都包含 `charlie_stage_post` prefab（查理舞台）
- **状态**: ✅ **可以通过 hook layout 处理**（两个 layout 都需要）

#### 5. **Oasis (绿洲)**
- **类型**: Layout + Prefab
- **Layout 名称**: `Oasis`
- **Prefab 名称**: `oasislake`
- **定义位置**: `src/map/layouts.lua:967`
- **说明**: 绿洲 layout，包含 `oasislake` prefab
- **状态**: ✅ **可以通过 hook layout 处理**

#### 6. **Multiplayer Gate (多人传送门)**
- **类型**: Prefab (`multiplayer_portal`)
- **放置方式**: 出现在以下 layout 中：
  - `DefaultStart` (默认起始点)
  - `DefaultPlusStart` (默认+起始点)
  - `CaveStart` (洞穴起始点)
  - `GrottoStart` (洞穴入口起始点)
- **说明**: `multiplayer_portal` 是 prefab，但它是 layout 的一部分
- **结论**: ❓ **可以通过 hook layout 处理**，但需要确认是否处理起始点 layout（通常起始点不应该移动）

#### 7. **Junkyard (垃圾场)**
- **类型**: Layout + Prefab
- **Layout 名称**: `junk_yard`
- **Prefab 名称**: `junk_pile`、`junk_pile_big`、`storage_robot` 等
- **定义位置**: `src/map/layouts.lua:1375`
- **说明**: 垃圾场 layout，包含多个 prefab
- **状态**: ✅ **可以通过 hook layout 处理**

### 需要处理的 Layout 列表

根据调研结果，以下 layout **可以通过 hook layout 机制处理**：

1. ✅ `DefaultPigking` - 猪王（已实现）
2. ✅ `DragonflyArena` - 龙蝇竞技场（包含 `dragonfly_spawner` prefab）
3. ✅ `MoonbaseOne` - 月亮基地（包含 `moonbase` prefab）
4. ✅ `Charlie1` - 查理舞台 1（包含 `charlie_stage_post` prefab）
5. ✅ `Charlie2` - 查理舞台 2（包含 `charlie_stage_post` prefab）
6. ✅ `Oasis` - 绿洲（包含 `oasislake` prefab）
7. ✅ `junk_yard` - 垃圾场（包含多个 prefab）

**待确认**:
- ❓ `DefaultStart`、`DefaultPlusStart`、`CaveStart` 等起始点 layout（包含 `multiplayer_portal` prefab，但通常起始点不应该移动）

**无法通过 hook layout 处理**:
- ❌ `beequeenhive` - 通过 Room `BeeQueenBee` 的 `countprefabs` 直接放置，不是 layout
  - 如果需要处理，需要 hook room 的 prefab 放置机制（更复杂，需要额外调研）

### 实现方案

1. **修改 `PigkingHandler`**:
   - 重命名为更通用的名称（如 `LayoutHandler` 或 `SpecialLayoutHandler`）
   - 将 `IsPigkingLayout` 改为 `ShouldMoveLayout`，支持多个 layout 名称
   - 使用 layout 名称列表进行匹配

2. **Layout 名称匹配**:
   ```lua
   local SPECIAL_LAYOUTS = {
       "DefaultPigking",
       "DragonflyArena",
       "MoonbaseOne",
       "Charlie1",
       "Charlie2",
       "Oasis",
       "junk_yard",
   }
   
   function LayoutHandler.ShouldMoveLayout(layout_name)
       if not layout_name then
           return false
       end
       local layout_name_lower = string.lower(layout_name)
       for _, special_layout in ipairs(SPECIAL_LAYOUTS) do
           if layout_name_lower == string.lower(special_layout) then
               return true
           end
       end
       return false
   end
   ```

3. **保持向后兼容**:
   - 保留 `IsPigkingLayout` 函数（内部调用 `ShouldMoveLayout`）
   - 更新日志消息，使其更通用

### 注意事项

1. **Layout vs Prefab vs Room**:
   - **Layout**: 可以通过现有的 hook 机制处理（`object_layout.Convert`）
   - **Prefab**: 如果是 layout 的一部分，可以通过 hook layout 处理；如果是 room 直接放置的，需要额外机制
   - **Room**: 使用 `countprefabs` 直接放置的 prefab 无法通过 hook layout 处理

2. **起始点 Layout**: 
   - `DefaultStart` 等起始点 layout 包含 `multiplayer_portal`，但通常不应该移动起始点
   - 需要用户确认是否要处理这些 layout

3. **Layout 名称大小写**:
   - 所有 layout 名称在 `layouts.lua` 中都是首字母大写的格式（如 `DragonflyArena`）
   - 匹配时应该使用不区分大小写的比较

4. **测试**:
   - 每个 layout 都需要测试，确保移动逻辑正常工作
   - 特别要注意大型 layout（如 `DragonflyArena`）的移动是否正确
   - 确保 layout 中的所有 prefab 和 ground tiles 都正确移动

5. **BeeQueen 的特殊情况**:
   - `beequeenhive` 是通过 room 的 `countprefabs` 直接放置的，不是 layout
   - 如果需要处理，需要调研如何 hook room 的 prefab 放置机制
   - 可能需要 hook `PopulateVoronoi` 或相关的 room 处理函数

---

## 调研：单个 Prefab 的移动劫持方案

**需求**: 对于通过 room 的 `countprefabs` 直接放置的 prefab（如 `beequeenhive`），需要调研如何 hook 它们的放置过程以实现移动。

### Prefab 放置机制分析

#### 1. **通过 `countprefabs` 放置的 Prefab**

**流程**:
1. Room 定义中使用 `countprefabs` 指定要放置的 prefab 和数量
   ```lua
   AddRoom("BeeQueenBee", {
       contents = {
           countprefabs = {
               beequeenhive = 1,
           }
       }
   })
   ```

2. 在世界生成时，`Node:PopulateVoronoi` 方法处理 `countprefabs`
   - 位置: `src/map/graphnode.lua:330-426`
   - 获取放置点: `WorldSim:GetPointsForSite(self.id)` 返回 `points_x, points_y`
   - 调用: `self:AddEntity(prefab, points_x, points_y, current_pos_idx, ...)`

3. `Node:AddEntity` 方法
   - 位置: `src/map/graphnode.lua:238-245`
   - 检查 tile 是否是陆地
   - 调用: `PopulateWorld_AddEntity(prefab, tile_x, tile_y, ...)`

4. `PopulateWorld_AddEntity` 全局函数
   - 位置: `src/map/graphnode.lua:188-235`
   - 将 tile 坐标转换为世界坐标
   - 添加到 `entitiesOut[prefab]` 表中

#### 2. **Hook 点分析**

**方案 1: Hook `PopulateWorld_AddEntity` 全局函数** ⭐ **推荐**

**优点**:
- 简单直接，所有 prefab 放置都会经过这个函数
- 统一处理，不需要区分不同的放置方式
- 可以获取 prefab 名称和坐标

**实现思路**:
```lua
-- 在 modworldgenmain.lua 中
local graphnode = require("map/graphnode")
local original_PopulateWorld_AddEntity = graphnode.PopulateWorld_AddEntity

graphnode.PopulateWorld_AddEntity = function(prefab, tile_x, tile_y, tile_value, entitiesOut, width, height, prefab_list, prefab_data, rand_offset)
    -- 检查是否是特殊 prefab
    if ShouldMovePrefab(prefab) then
        -- 转换为世界坐标
        local world_x = (tile_x - width/2.0) * TILE_SCALE
        local world_y = (tile_y - height/2.0) * TILE_SCALE
        
        -- 查找合法坐标
        local new_world_x, new_world_y, found = LandEdgeFinder.FindNearestValidPosition(world_x, world_y, WorldSim)
        
        if found then
            -- 转换回 tile 坐标
            local new_tile_x = math.floor((width / 2) + 0.5 + (new_world_x / TILE_SCALE))
            local new_tile_y = math.floor((height / 2) + 0.5 + (new_world_y / TILE_SCALE))
            
            -- 使用新坐标调用原始函数
            return original_PopulateWorld_AddEntity(prefab, new_tile_x, new_tile_y, tile_value, entitiesOut, width, height, prefab_list, prefab_data, rand_offset)
        end
    end
    
    -- 普通 prefab，使用原始坐标
    return original_PopulateWorld_AddEntity(prefab, tile_x, tile_y, tile_value, entitiesOut, width, height, prefab_list, prefab_data, rand_offset)
end
```

**注意事项**:
- `PopulateWorld_AddEntity` 是**全局函数**（在 `graphnode.lua` 中定义，没有 `local` 关键字）
- 可以通过 `_G.PopulateWorld_AddEntity` 或直接通过 `PopulateWorld_AddEntity` 访问（需要先 `require("map/graphnode")` 加载模块）
- 需要验证 hook 后不会影响 layout 中的 prefab（layout 已经通过 layout hook 处理）

**方案 2: Hook `Node:AddEntity` 方法**

**优点**:
- 可以访问 Node 信息（如 node_id）
- 在 tile 验证之后，确保是陆地 tile

**缺点**:
- 需要 hook Node 类的 metatable
- 实现较复杂

**方案 3: Hook `Node:PopulateVoronoi` 方法**

**优点**:
- 可以在获取放置点之前修改逻辑
- 可以完全控制 prefab 的放置过程

**缺点**:
- 需要重新实现整个 `PopulateVoronoi` 逻辑
- 复杂度高，容易出错

### 关键函数签名

#### `PopulateWorld_AddEntity`
```lua
function PopulateWorld_AddEntity(prefab, tile_x, tile_y, tile_value, entitiesOut, width, height, prefab_list, prefab_data, rand_offset)
    -- prefab: prefab 名称（字符串）
    -- tile_x, tile_y: tile 坐标（整数）
    -- tile_value: tile 类型值
    -- entitiesOut: 输出表，entitiesOut[prefab] 存储所有该 prefab 的坐标
    -- width, height: 地图尺寸（tile 单位）
    -- prefab_list: prefab 计数表
    -- prefab_data: prefab 的额外数据
    -- rand_offset: 是否添加随机偏移（boolean）
    
    -- 内部逻辑：
    -- 1. ReserveTile(tile_x, tile_y)
    -- 2. 转换为世界坐标: x = (tile_x - width/2.0) * TILE_SCALE
    -- 3. 如果 rand_offset，添加随机偏移
    -- 4. 添加到 entitiesOut[prefab] 表
end
```

#### `Node:AddEntity`
```lua
function Node:AddEntity(prefab, points_x, points_y, current_pos_idx, entitiesOut, width, height, prefab_list, prefab_data, rand_offset)
    -- self: Node 实例
    -- prefab: prefab 名称
    -- points_x, points_y: 放置点数组
    -- current_pos_idx: 当前使用的点索引
    -- 其他参数同 PopulateWorld_AddEntity
    
    -- 内部逻辑：
    -- 1. 检查 tile 是否是陆地
    -- 2. 调用 PopulateWorld_AddEntity
end
```

### 坐标转换

**Tile 坐标 → 世界坐标**:
```lua
local world_x = (tile_x - width/2.0) * TILE_SCALE
local world_y = (tile_y - height/2.0) * TILE_SCALE
```

**世界坐标 → Tile 坐标**:
```lua
local tile_x = math.floor((width / 2) + 0.5 + (world_x / TILE_SCALE))
local tile_y = math.floor((height / 2) + 0.5 + (world_y / TILE_SCALE))
```

### 需要移动的 Prefab 列表

根据之前的调研，以下 prefab 需要通过 hook 机制处理：

1. **`beequeenhive`** - 蜜蜂女王蜂巢
   - 通过 Room `BeeQueenBee` 的 `countprefabs` 放置
   - 位置: `src/map/rooms/forest/bee.lua:19`

### 实现建议

1. **创建 `prefab_handler.lua` 模块**:
   - 定义需要移动的 prefab 列表
   - 实现 `ShouldMovePrefab(prefab_name)` 函数
   - 实现 `ProcessPrefabPosition` 函数（类似 `ProcessPosition`）

2. **Hook `PopulateWorld_AddEntity`**:
   - 在 `modworldgenmain.lua` 中 hook
   - 检查 prefab 名称
   - 如果需要移动，修改 tile 坐标后调用原始函数

3. **坐标验证**:
   - 确保新坐标是合法的 tile 坐标（整数）
   - 确保新坐标在地图范围内
   - 确保新坐标是陆地 tile

### 注意事项

1. **`PopulateWorld_AddEntity` 的访问方式**:
   - 需要确认这个函数是全局函数还是模块导出
   - 可能需要通过 `require("map/graphnode")` 访问，或者直接 hook 全局函数

2. **`rand_offset` 参数**:
   - 如果 `rand_offset == true`，原始函数会添加随机偏移
   - 移动后的坐标也需要考虑这个偏移

3. **`ReserveTile` 调用**:
   - 原始函数会调用 `WorldSim:ReserveTile(tile_x, tile_y)`
   - 如果修改了坐标，需要确保新坐标也被正确保留

4. **性能考虑**:
   - 每个 prefab 放置都会经过 hook，需要快速判断
   - 可以使用简单的字符串匹配或哈希表查找

5. **与 Layout Hook 的协调**:
   - Layout 中的 prefab 也会经过 `PopulateWorld_AddEntity`
   - 需要区分是 layout 中的 prefab 还是直接放置的 prefab
   - 或者统一处理，layout hook 只处理 layout 整体移动，prefab hook 处理单个 prefab

### 待验证的问题

1. **`PopulateWorld_AddEntity` 的访问方式**: ✅ **已确认**
   - 是**全局函数**（在 `graphnode.lua:188` 定义，没有 `local` 关键字）
   - 可以通过 `_G.PopulateWorld_AddEntity` 或直接访问（需要先 `require("map/graphnode")`）
   - Hook 方式: `local original = _G.PopulateWorld_AddEntity` 或 `local graphnode = require("map/graphnode"); local original = graphnode.PopulateWorld_AddEntity`

2. **Layout 中的 Prefab**:
   - Layout 中的 prefab 是否也会经过 `PopulateWorld_AddEntity`？
   - 如果是，如何区分 layout prefab 和直接放置的 prefab？

3. **坐标修改的时机**:
   - 在 `PopulateWorld_AddEntity` 中修改坐标是否会影响其他系统？
   - 是否需要同时修改 `ReserveTile` 的调用？

---

