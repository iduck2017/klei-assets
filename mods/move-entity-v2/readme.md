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

