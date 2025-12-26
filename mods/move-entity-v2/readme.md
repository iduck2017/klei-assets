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

## 调研：新增需要移动的元素（洞穴入口、虫洞、麋鹿鹅生成器、复活石、小丑牌游戏机）

### 需求描述

用户需要添加以下元素到移动列表中：
1. **洞穴入口** (caveEntrance)
2. **虫洞** (wormhole)
3. **麋鹿鹅生成器** (moosegoose spawner)
4. **复活石** (resurrection stone / touchstone)
5. **小丑牌游戏机** (balatro machine / card game machine)

用户要求优先使用 layout 形式移动。

### 源码调研结果

#### 1. 洞穴入口 (Cave Entrance)

**Layout 名称**: `"CaveEntrance"`

**源码位置**:
- `src/map/layouts.lua:718` - Layout 定义
- `src/map/static_layouts/cave_entrance.lua` - 静态布局文件
- `src/prefabs/cave_entrance.lua` - Prefab 定义

**Layout 信息**:
- 包含 `cave_entrance` prefab
- 用于连接主世界和洞穴世界

**注意**: 只需要处理主世界的洞穴入口，不需要处理洞穴出口

#### 2. 虫洞 (Wormhole)

**Layout 名称**: `"WormholeGrass"`

**源码位置**:
- `src/map/layouts.lua:643` - Layout 定义
- `src/prefabs/wormhole.lua` - Prefab 定义
- `src/map/network.lua:850-885` - 虫洞配对逻辑

**Layout 信息**:
- 普通草地虫洞，最基本的虫洞类型
- 虫洞通常成对出现，通过 `teleporter` 组件连接

**注意**: 只需要处理最基本的 `WormholeGrass`，不需要处理其他变体（疯狂虫洞、理智虫洞等）

#### 3. 麋鹿鹅生成器 (Moose Goose Spawner)

**Layout 名称**: `"MooseNest"`

**源码位置**:
- `src/map/layouts.lua:891` - Layout 定义
- `src/map/static_layouts/moose_nest.lua` - 静态布局文件
- `src/prefabs/mooseegg.lua` - 包含 `moose_nesting_ground` prefab
- `src/components/moosespawner.lua` - 生成器组件

**Layout 信息**:
- 包含 `moose_nesting_ground` prefab（麋鹿鹅巢穴）
- 在春季时通过 `moosespawner` 组件生成麋鹿鹅
- 布局中可能包含随机树木

**相关 Prefab**:
- `moose_nesting_ground` - 巢穴 prefab（在 layout 中）
- `moose` - 麋鹿鹅（运行时生成）
- `mooseegg` - 麋鹿鹅蛋（运行时生成）

#### 4. 复活石 (Resurrection Stone / Touchstone)

**Layout 名称**: 多个 Layout 变体

**源码位置**:
- `src/map/layouts.lua:264-266` - Layout 定义
- `src/map/static_layouts/resurrectionstone.lua` - 静态布局文件
- `src/prefabs/resurrectionstone.lua` - Prefab 定义

**Layout 列表**:
- `"ResurrectionStone"` - 标准复活石
- `"ResurrectionStoneLit"` - 已激活的复活石
- `"ResurrectionStoneWinter"` - 冬季复活石

**Layout 信息**:
- 所有变体都包含 `resurrectionstone` prefab
- 复活石有激活/未激活状态，通过 `cooldown` 组件管理

**相关配置**:
- 在世界生成设置中称为 `"touchstone"`
- 在 `tasksets/forest.lua` 和 `tasksets/caves.lua` 中配置数量

#### 5. 小丑牌游戏机 (Balatro Machine)

**Layout 名称**: `"Balatro"`

**源码位置**:
- `src/map/layouts.lua:445` - Layout 定义
- `src/map/static_layouts/balatro.lua` - 静态布局文件
- `src/prefabs/balatro_machine.lua` - Prefab 定义
- `src/map/maptags.lua:129` - 通过 `Balatro_Spawner` 标签生成

**Layout 信息**:
- 包含 `balatro_machine` prefab
- 包含 `balatro_card_area` 区域，随机生成 `playing_card` prefab
- 通过世界生成标签 `Balatro_Spawner` 控制生成

**相关配置**:
- 在世界生成设置中称为 `"balatro"`
- 可以通过世界生成设置禁用

### 实现建议

#### Layout 列表更新

所有元素都**以 Layout 形式存在**，可以直接添加到 `SPECIAL_LAYOUTS` 列表：

```lua
local SPECIAL_LAYOUTS = {
    -- 现有布局...
    "DefaultPigking",
    "DragonflyArena",
    -- ...
    
    -- 新增布局
    "CaveEntrance",              -- 洞穴入口（仅主世界入口）
    "WormholeGrass",              -- 虫洞（基础类型）
    "MooseNest",                 -- 麋鹿鹅生成器
    "ResurrectionStone",         -- 复活石（标准）
    "ResurrectionStoneLit",     -- 复活石（已激活）
    "ResurrectionStoneWinter",   -- 复活石（冬季）
    "Balatro",                   -- 小丑牌游戏机
}
```

#### 注意事项

1. **洞穴入口**: 只需要处理主世界的 `CaveEntrance`，不需要处理洞穴世界的 `CaveExit`

2. **虫洞**: 只需要处理最基本的 `WormholeGrass`，不需要处理其他变体（疯狂虫洞、理智虫洞等）

3. **复活石变体**: 复活石有 3 个 Layout 变体，建议全部添加以确保所有类型的复活石都能被移动

4. **虫洞配对**: 虫洞通常成对出现，移动时需要注意配对逻辑，但基本的 Layout Hook 应该已经能够处理

5. **麋鹿鹅生成器**: `MooseNest` 布局包含 `moose_nesting_ground` prefab，移动布局即可移动生成器

6. **小丑牌游戏机**: `Balatro` 布局通过世界生成标签控制，移动布局即可移动游戏机

### 待实现

- [ ] 将上述 Layout 名称添加到 `SPECIAL_LAYOUTS` 列表
  - `"CaveEntrance"` - 洞穴入口（仅主世界）
  - `"WormholeGrass"` - 虫洞（基础类型）
  - `"MooseNest"` - 麋鹿鹅生成器
  - `"ResurrectionStone"` - 复活石（标准）
  - `"ResurrectionStoneLit"` - 复活石（已激活）
  - `"ResurrectionStoneWinter"` - 复活石（冬季）
  - `"Balatro"` - 小丑牌游戏机
- [ ] 测试每个 Layout 的移动是否正常工作
- [ ] 验证虫洞配对是否仍然正常（如果虫洞被移动）
- [ ] 验证复活石的不同变体是否都能正确移动
- [ ] 验证麋鹿鹅生成器移动后，麋鹿鹅生成逻辑是否正常

### 相关文件

- `src/map/layouts.lua` - 所有 Layout 定义
- `src/map/static_layouts/` - 静态布局文件目录
- `mods/move-entity-v2/scripts/pigking_handler.lua` - 需要更新的文件

---

## 调研：池塘的距离排斥规则

### 需求描述

用户需要添加池塘到移动列表中，但有以下特殊要求：
1. **池塘需要遵循距离排斥规则**：池塘需要距离主要建筑 >= 8 tiles
2. **池塘彼此之间不需要互相排斥**：池塘放置后，不需要删除周围的 validpos，允许池塘彼此靠近

### 源码调研结果

#### 池塘的放置方式

**主要方式：通过 Prefab 直接放置**

池塘主要通过 room 的 `countprefabs` 直接放置，而不是通过 layout：

**源码位置**:
- `src/prefabs/pond.lua` - 池塘 prefab 定义
- `src/map/rooms/forest/pigs.lua:129-144` - `Pondopolis` 房间示例

**Prefab 类型**:
- `"pond"` - 普通池塘（青蛙池塘）
- `"pond_mos"` - 蚊子池塘
- `"pond_cave"` - 洞穴池塘

**放置示例**:
```lua
-- src/map/rooms/forest/pigs.lua
AddRoom("Pondopolis", {
    contents = {
        countprefabs = {
            pond = function () return 5 + math.random(3) end
        },
    }
})
```

#### Layout 中的池塘

虽然有一些包含池塘的 layout，但池塘本身主要是通过 prefab 放置的：

**相关 Layout**:
- `"DeciduousPond"` - 落叶池塘布局（但布局中不包含池塘 prefab，只有树和花）
- `"PondSinkhole"` - 池塘天坑布局（包含 `pondarea` 区域，但池塘是通过区域函数生成的）

**结论**: 池塘主要通过 prefab hook 处理，而不是 layout hook。

### 实现方案

#### 1. 添加到 SPECIAL_PREFABS 列表

需要将池塘 prefab 添加到 `SPECIAL_PREFABS` 列表中：

```lua
-- prefab_handler.lua
local SPECIAL_PREFABS = {
    -- 现有 prefab...
    "pond",        -- 普通池塘
    "pond_mos",    -- 蚊子池塘
    "pond_cave",   -- 洞穴池塘
}
```

#### 2. 修改距离排斥逻辑

**关键点**: 池塘需要距离主要建筑 >= 8 tiles，但池塘彼此之间不需要互相排斥。

**实现方式**:
1. 池塘放置后，**不调用** `RemovePositionsNearby` 来删除周围的 validpos
2. 但池塘仍然会从 `VALID_POSITIONS` 中查找位置，确保距离主要建筑 >= 8 tiles

**代码修改**:
- 在 `prefab_handler.lua` 的 `ProcessPrefabPosition` 函数中，添加一个判断：
  - 如果是池塘 prefab，找到合法位置后，**不调用** `RemovePositionsNearby`
  - 如果是主要建筑（layout 或其他 prefab），找到合法位置后，**调用** `RemovePositionsNearby`

#### 3. 区分"主要建筑"和"池塘"

**方案 A: 在 prefab_handler 中添加判断**

```lua
-- prefab_handler.lua
local POND_PREFABS = {
    "pond",
    "pond_mos",
    "pond_cave",
}

function PrefabHandler.IsPondPrefab(prefab)
    if not prefab then
        return false
    end
    for _, pond_prefab in ipairs(POND_PREFABS) do
        if prefab == pond_prefab then
            return true
        end
    end
    return false
end

function PrefabHandler.ProcessPrefabPosition(prefab, tile_x, tile_y, width, height, world)
    -- ... 查找合法位置 ...
    
    if found_valid then
        -- 只有非池塘的 prefab 才需要删除周围的 validpos
        if not PrefabHandler.IsPondPrefab(prefab) then
            LandEdgeFinder.RemovePositionsNearby(new_tile_x, new_tile_y, 8)
        end
        
        -- ... 日志输出 ...
    end
end
```

**方案 B: 在 pigking_handler 中添加判断**

类似地，在 `pigking_handler.lua` 中也可以添加判断，但 layout 中通常不包含池塘，所以主要是在 prefab_handler 中处理。

### 注意事项

1. **池塘类型**: 需要处理所有三种池塘类型（`pond`, `pond_mos`, `pond_cave`）

2. **距离计算**: 池塘仍然需要距离主要建筑 >= 8 tiles，只是池塘彼此之间不需要互相排斥

3. **VALID_POSITIONS 的影响**: 
   - 当主要建筑放置后，会删除周围 8 tiles 的 validpos
   - 池塘放置后，不会删除周围的 validpos
   - 这意味着池塘可以彼此靠近，但不会靠近主要建筑

4. **查找逻辑**: 池塘在查找合法位置时，仍然使用 `FindNearestValidPosition`，这会确保找到的位置距离主要建筑 >= 8 tiles（因为主要建筑周围的 validpos 已被删除）

### 待实现

- [ ] 将 `"pond"`, `"pond_mos"`, `"pond_cave"` 添加到 `SPECIAL_PREFABS` 列表
- [ ] 在 `prefab_handler.lua` 中添加 `IsPondPrefab` 函数
- [ ] 修改 `ProcessPrefabPosition` 函数，池塘放置后不调用 `RemovePositionsNearby`
- [ ] 测试池塘是否能够正确移动到距离主要建筑 >= 8 tiles 的位置
- [ ] 测试池塘彼此之间是否可以靠近（距离 < 8 tiles）

### 相关文件

- `src/prefabs/pond.lua` - 池塘 prefab 定义
- `src/map/rooms/forest/pigs.lua` - 池塘放置示例
- `mods/move-entity-v2/scripts/prefab_handler.lua` - 需要更新的文件

---

## 调研：排除 Layout 中的池塘 Prefab

### 需求描述

用户发现一个问题：池塘不能是 moosegoose 池塘。也就是说，在检查 prefab 是否是池塘时，需要排除 layout 里面的对象。

**问题场景**：
- `MooseNest` layout 中包含 `pond` prefab（见 `src/map/static_layouts/moose_nest.lua:65`）
- 如果池塘是作为 layout 的一部分放置的，它不应该被 prefab hook 处理（因为 layout 已经通过 layout hook 整体移动了）
- 只有通过 room 的 `countprefabs` 直接放置的池塘才应该被 prefab hook 处理

### 源码分析

#### 1. Layout 中的 Prefab 放置流程

**Layout 放置流程**：
```
obj_layout.Convert()
  → obj_layout.ReserveAndPlaceLayout()
    → add_entity.fn(prefab, ...)  // add_entity.fn = Node:AddEntity
      → PopulateWorld_AddEntity(prefab, ...)
```

**直接放置流程**：
```
Node:PopulateVoronoi()
  → PopulateWorld_AddEntity(prefab, ...)
```

**关键发现**：
- 两种方式最终都调用 `PopulateWorld_AddEntity`
- Layout 中的 prefab 通过 `add_entity.fn`（即 `Node:AddEntity`）调用
- 直接放置的 prefab 直接调用 `PopulateWorld_AddEntity`

#### 2. 区分方案

**方案 1: 使用全局标记（推荐）**

**思路**：
- 在 layout hook 中，当处理 layout 时，设置一个全局标记
- 在 prefab hook 中检查这个标记，如果正在处理 layout，则跳过该 prefab

**实现**：
```lua
-- layout_hook.lua
obj_layout.ReserveAndPlaceLayout = function(node_id, layout, prefabs, add_entity, position, world)
    -- 设置全局标记，表示正在处理 layout
    _G.move_entity_v2_processing_layout = true
    
    local result = original_ReserveAndPlaceLayout(node_id, layout, prefabs, add_entity, position, world)
    
    -- 清除标记
    _G.move_entity_v2_processing_layout = false
    
    return result
end

-- prefab_hook.lua
_G.PopulateWorld_AddEntity = function(prefab, tile_x, tile_y, ...)
    -- 如果正在处理 layout，跳过 prefab hook
    if _G.move_entity_v2_processing_layout then
        return original_PopulateWorld_AddEntity(prefab, tile_x, tile_y, ...)
    end
    
    -- 正常处理 prefab
    if PrefabHandler.ShouldMovePrefab(prefab) then
        -- ...
    end
end
```

**优点**：
- 实现简单
- 不需要修改 `prefab_data` 或调用链
- 逻辑清晰

**缺点**：
- 使用全局变量，需要注意线程安全（但 DST 是单线程的，所以问题不大）
- 如果 `ReserveAndPlaceLayout` 抛出异常，标记可能不会被清除（需要 try-finally 或 pcall）

**方案 2: 在 prefab_data 中添加标记**

**思路**：
- 在 layout hook 中，修改 `add_entity.fn`，在调用时添加标记到 `prefab_data`
- 在 prefab hook 中检查 `prefab_data` 是否有标记

**实现**：
```lua
-- layout_hook.lua
local function wrap_add_entity(original_add_entity, layout_name)
    return {
        fn = function(prefab, points_x, points_y, current_pos_idx, entitiesOut, width, height, prefab_list, prefab_data, rand_offset)
            -- 在 prefab_data 中添加标记
            if not prefab_data then
                prefab_data = {}
            end
            prefab_data._from_layout = layout_name
            
            return original_add_entity.fn(prefab, points_x, points_y, current_pos_idx, entitiesOut, width, height, prefab_list, prefab_data, rand_offset)
        end,
        args = original_add_entity.args
    }
end

-- prefab_hook.lua
_G.PopulateWorld_AddEntity = function(prefab, tile_x, tile_y, tile_value, entitiesOut, width, height, prefab_list, prefab_data, rand_offset)
    -- 如果 prefab_data 中有 _from_layout 标记，说明来自 layout，跳过
    if prefab_data and prefab_data._from_layout then
        return original_PopulateWorld_AddEntity(prefab, tile_x, tile_y, tile_value, entitiesOut, width, height, prefab_list, prefab_data, rand_offset)
    end
    
    -- 正常处理 prefab
    if PrefabHandler.ShouldMovePrefab(prefab) then
        -- ...
    end
end
```

**优点**：
- 不依赖全局变量
- 可以知道 prefab 来自哪个 layout（用于调试）

**缺点**：
- 需要修改 `add_entity` 对象，可能影响其他逻辑
- 需要确保 `prefab_data` 表存在

**方案 3: 检查调用栈**

**思路**：
- 使用 Lua 的 `debug` 库检查调用栈
- 如果调用栈中包含 `ReserveAndPlaceLayout`，说明来自 layout

**实现**：
```lua
-- prefab_hook.lua
local function is_from_layout()
    local info = debug.getinfo(3, "n")
    if info then
        return info.name == "ReserveAndPlaceLayout"
    end
    return false
end

_G.PopulateWorld_AddEntity = function(prefab, tile_x, tile_y, ...)
    -- 检查是否来自 layout
    if is_from_layout() then
        return original_PopulateWorld_AddEntity(prefab, tile_x, tile_y, ...)
    end
    
    -- 正常处理 prefab
    if PrefabHandler.ShouldMovePrefab(prefab) then
        -- ...
    end
end
```

**优点**：
- 不需要修改其他代码
- 自动检测

**缺点**：
- 依赖 `debug` 库，可能在某些环境中不可用
- 性能开销（每次调用都检查调用栈）
- 调用栈深度需要调整（可能不稳定）

### 推荐实现

**推荐使用方案 1（全局标记）**：

**理由**：
1. **实现简单**：只需要在 layout hook 中设置和清除标记
2. **性能好**：只是一个布尔值检查
3. **逻辑清晰**：明确表示"正在处理 layout"
4. **兼容性好**：不依赖 `debug` 库或修改 `prefab_data`

**实现要点**：
1. 在 `layout_hook.lua` 的 `ReserveAndPlaceLayout` hook 中设置和清除全局标记
2. 使用 `pcall` 确保即使出错也能清除标记
3. 在 `prefab_hook.lua` 中检查标记，如果正在处理 layout，直接跳过

**代码示例**：
```lua
-- layout_hook.lua
obj_layout.ReserveAndPlaceLayout = function(node_id, layout, prefabs, add_entity, position, world)
    -- 设置全局标记
    _G.move_entity_v2_processing_layout = true
    
    -- 使用 pcall 确保即使出错也能清除标记
    local success, result = pcall(function()
        return original_ReserveAndPlaceLayout(node_id, layout, prefabs, add_entity, position, world)
    end)
    
    -- 清除标记
    _G.move_entity_v2_processing_layout = false
    
    if success then
        return result
    else
        error(result)  -- 重新抛出错误
    end
end

-- prefab_hook.lua
_G.PopulateWorld_AddEntity = function(prefab, tile_x, tile_y, tile_value, entitiesOut, width, height, prefab_list, prefab_data, rand_offset)
    -- 如果正在处理 layout，跳过 prefab hook（layout 已经通过 layout hook 处理）
    if _G.move_entity_v2_processing_layout then
        return original_PopulateWorld_AddEntity(prefab, tile_x, tile_y, tile_value, entitiesOut, width, height, prefab_list, prefab_data, rand_offset)
    end
    
    -- 正常处理 prefab
    if PrefabHandler.ShouldMovePrefab(prefab) then
        -- ...
    end
end
```

### 注意事项

1. **异常处理**：使用 `pcall` 确保即使 `ReserveAndPlaceLayout` 抛出异常，标记也能被清除

2. **嵌套 Layout**：如果 layout 中嵌套调用其他 layout（理论上不应该发生），全局标记仍然有效

3. **线程安全**：DST 是单线程的，所以全局变量是安全的

4. **性能影响**：全局标记检查的性能开销可以忽略不计

### 待实现

- [ ] 在 `layout_hook.lua` 的 `ReserveAndPlaceLayout` hook 中添加全局标记设置和清除
- [ ] 在 `prefab_hook.lua` 中添加标记检查，跳过来自 layout 的 prefab
- [ ] 测试 `MooseNest` layout 中的池塘是否被正确排除
- [ ] 测试直接放置的池塘是否仍然被正确处理

### 相关文件

- `src/map/static_layouts/moose_nest.lua` - `MooseNest` layout 定义（包含 `pond` prefab）
- `src/map/object_layout.lua:481` - Layout 中 prefab 的调用位置
- `mods/move-entity-v2/scripts/layout_hook.lua` - 需要修改的文件
- `mods/move-entity-v2/scripts/prefab_hook.lua` - 需要修改的文件

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

## 调研：远离已放置的特殊 Layout 和 Prefab

**需求**: 在移动特殊 layout 或 prefab 时，不仅需要远离岸边（距离 >= 6 tiles），还需要远离已经放置的其他特殊 layout 和 prefab（距离 >= 6 tiles）。

### 问题分析

当前实现中，`LandEdgeFinder.PrecomputeValidPositions` 只考虑了距离边缘的距离，没有考虑已放置的特殊 layout 和 prefab 的位置。这可能导致：
1. 多个特殊 layout/prefab 被放置在相近的位置
2. 新放置的 layout/prefab 可能靠近已放置的特殊 layout/prefab

### 实现方案

#### 方案 1: 动态更新合法坐标集合 ⭐ **推荐**

**思路**:
1. 在预计算时，只考虑距离边缘 >= 6 tiles 的坐标
2. 当放置一个特殊 layout/prefab 后，从 `VALID_POSITIONS` 中移除距离该位置 < 6 tiles 的坐标
3. 后续查找时，自动排除这些已被占用的区域

**优点**:
- 实现简单，只需要在放置后更新 `VALID_POSITIONS`
- 性能好，不需要在每次查找时重新计算
- 逻辑清晰，逐步缩小可用区域

**缺点**:
- 如果放置顺序不当，可能导致后续 layout/prefab 找不到合法位置

**实现步骤**:
1. 在 `LandEdgeFinder` 中添加 `RemovePositionsNearby(tile_x, tile_y, min_distance)` 函数
2. 在 `PigkingHandler.ProcessPosition` 中，放置 layout 后调用该函数
3. 在 `PrefabHandler.ProcessPrefabPosition` 中，放置 prefab 后调用该函数

#### 方案 2: 在查找时实时检查

**思路**:
1. 维护一个已放置的特殊 layout/prefab 位置列表
2. 在 `FindNearestValidPosition` 中，对每个候选坐标检查：
   - 距离边缘 >= 6 tiles
   - 距离所有已放置的特殊 layout/prefab >= 6 tiles

**优点**:
- 不需要修改预计算逻辑
- 可以灵活处理放置顺序

**缺点**:
- 每次查找都需要遍历所有已放置的位置，性能较差
- 如果已放置的位置很多，查找会变慢

#### 方案 3: 混合方案

**思路**:
1. 预计算时只考虑距离边缘 >= 6 tiles
2. 在查找时，实时检查距离已放置的特殊 layout/prefab >= 6 tiles
3. 如果找到合法位置，放置后更新 `VALID_POSITIONS`（移除附近坐标）

**优点**:
- 结合两种方案的优点
- 性能较好，逻辑清晰

**缺点**:
- 实现稍复杂

### 距离计算

**Tile 坐标距离**:
```lua
local function TileDistance(tile_x1, tile_y1, tile_x2, tile_y2)
    local dx = tile_x1 - tile_x2
    local dy = tile_y1 - tile_y2
    return math.sqrt(dx * dx + dy * dy)
end
```

**世界坐标距离**:
```lua
local function WorldDistance(world_x1, world_y1, world_x2, world_y2)
    local dx = world_x1 - world_x2
    local dy = world_y1 - world_y2
    return math.sqrt(dx * dx + dy * dy) / TILE_SCALE  -- 转换为 tile 单位
end
```

### 已放置位置记录

需要记录的信息：
- Layout 名称（用于日志）
- 最终放置的世界坐标 (world_x, world_y)
- 对应的 tile 坐标 (tile_x, tile_y)

**数据结构**:
```lua
local PLACED_POSITIONS = {
    {
        type = "layout",  -- 或 "prefab"
        name = "DefaultPigking",
        world_x = 254.00,
        world_y = 230.00,
        tile_x = 276,
        tile_y = 270
    },
    -- ...
}
```

### 实现建议

**推荐使用方案 1（动态更新合法坐标集合）**:

1. **在 `LandEdgeFinder` 中添加函数**:
   ```lua
   -- 移除距离指定位置 < min_distance 的合法坐标
   function LandEdgeFinder.RemovePositionsNearby(tile_x, tile_y, min_distance)
       min_distance = min_distance or 6
       local removed_count = 0
       
       for i = #VALID_POSITIONS, 1, -1 do
           local pos = VALID_POSITIONS[i]
           local dx = pos.tx - tile_x
           local dy = pos.ty - tile_y
           local dist = math.sqrt(dx * dx + dy * dy)
           
           if dist < min_distance then
               table.remove(VALID_POSITIONS, i)
               removed_count = removed_count + 1
           end
       end
       
       if removed_count > 0 then
           print(string.format(
               "[Move Entity V2] [LandEdgeFinder] 移除了 %d 个距离 tile (%d, %d) < %d tiles 的合法坐标",
               removed_count, tile_x, tile_y, min_distance
           ))
       end
       
       return removed_count
   end
   ```

2. **在 `PigkingHandler.ProcessPosition` 中调用**:
   ```lua
   if found_valid then
       -- 转换为 tile 坐标
       local new_tile_x, new_tile_y = WorldToTileCoords(new_rcx, new_rcy, ...)
       
       -- 移除附近 6 tiles 的合法坐标
       LandEdgeFinder.RemovePositionsNearby(new_tile_x, new_tile_y, 6)
       
       return new_rcx, new_rcy, true
   end
   ```

3. **在 `PrefabHandler.ProcessPrefabPosition` 中调用**:
   ```lua
   if found_valid then
       -- 移除附近 6 tiles 的合法坐标
       LandEdgeFinder.RemovePositionsNearby(new_tile_x, new_tile_y, 6)
       
       return new_tile_x, new_tile_y, true
   end
   ```

### 注意事项

1. **放置顺序**:
   - 如果多个 layout/prefab 需要移动，放置顺序可能影响结果
   - 建议按照重要性或生成顺序处理

2. **坐标转换**:
   - Layout 使用世界坐标 (world_x, world_y)
   - Prefab 使用 tile 坐标 (tile_x, tile_y)
   - 需要统一转换后再比较距离

3. **边界情况**:
   - 如果移除后 `VALID_POSITIONS` 为空，后续 layout/prefab 可能找不到合法位置
   - 需要处理这种情况（返回 false 或使用原始坐标）

4. **性能考虑**:
   - 每次移除需要遍历 `VALID_POSITIONS`，如果坐标很多可能较慢
   - 可以考虑使用更高效的数据结构（如空间索引）

### 待实现

- [ ] 在 `LandEdgeFinder` 中添加 `RemovePositionsNearby` 函数
- [ ] 在 `PigkingHandler.ProcessPosition` 中调用移除函数
- [ ] 在 `PrefabHandler.ProcessPrefabPosition` 中调用移除函数
- [ ] 添加日志记录，显示移除了多少坐标
- [ ] 测试多个 layout/prefab 的放置顺序

---

## 调研：将所有有效坐标的地皮替换为木板地皮

### 需求描述

将所有预计算的有效坐标（距离边缘 >= 6 tiles 的陆地 tile）的地皮替换为木板地皮（WOODFLOOR），以便在游戏中清晰标识这些安全区域。

### 关键 API 调研

#### 1. 设置 Tile 的方法

在世界生成阶段，可以使用以下方法设置 tile：

**方法 1: `WorldSim:SetTile(x, y, tile)`**
- 参数：
  - `x, y`: tile 坐标（整数，从 0 开始）
  - `tile`: tile 类型常量（如 `WORLD_TILES.WOODFLOOR`）
- 使用场景：世界生成阶段（`modworldgenmain.lua`）
- 示例：
  ```lua
  local WorldSim = require("map/WorldSim")
  WorldSim:SetTile(tile_x, tile_y, WORLD_TILES.WOODFLOOR)
  ```

**方法 2: `world:SetTile(x, y, tile)`**
- 参数：同上
- 使用场景：世界生成阶段，当有 `world` 对象时
- 示例：
  ```lua
  world:SetTile(tile_x, tile_y, WORLD_TILES.WOODFLOOR)
  ```

**方法 3: `TheWorld.Map:SetTile(x, y, tile)`**
- 参数：同上
- 使用场景：游戏运行时（`modmain.lua`）
- 注意：会触发 `onterraform` 事件
- 示例：
  ```lua
  TheWorld.Map:SetTile(tile_x, tile_y, WORLD_TILES.WOODFLOOR)
  ```

#### 2. 木板地皮常量

- **常量名**: `WORLD_TILES.WOODFLOOR`
- **值**: `10`（定义在 `src/constants.lua:684`）
- **用途**: 木板地皮，玩家可以制作并放置的地皮类型

#### 3. 相关代码位置

**设置 Tile 的示例代码**:
- `src/map/object_layout.lua:392`: 在布局放置时设置地皮
  ```lua
  world:SetTile(x, y, layout.ground_types[layout.ground[rw][clmn]], 1)
  ```
- `src/map/ocean_gen.lua:94`: 在海洋生成时设置地皮
  ```lua
  world:SetTile(x, y, ground)
  ```
- `src/map/room_functions.lua:18`: 在房间函数中设置地皮
  ```lua
  WorldSim:SetTile(points_x[current_pos_idx], points_y[current_pos_idx], current_layer.tile)
  ```

**地皮替换组件**:
- `src/components/terraformer.lua:26`: 使用 `map:SetTile(x, y, turf)` 替换地皮
- `src/prefabs/turfs.lua:15`: 地皮物品部署时使用 `map:SetTile(x, y, tile)`

### 实现方案

#### 方案 1: 在预计算后立即替换（推荐）⭐

在 `LandEdgeFinder.PrecomputeValidPositions` 函数中，每找到一个有效坐标后立即替换地皮。

**优点**:
- 时机准确：在预计算时立即替换，确保所有有效坐标都被处理
- 代码集中：逻辑集中在 `land_edge_finder.lua` 中
- 性能好：只需遍历一次 `VALID_POSITIONS`

**实现步骤**:
1. 在 `PrecomputeValidPositions` 函数中，添加 `world` 参数（如果还没有）
2. 在找到有效坐标并添加到 `VALID_POSITIONS` 后，立即调用 `world:SetTile(x, y, WORLD_TILES.WOODFLOOR)`
3. 添加日志记录，显示替换了多少个 tile

**代码示例**:
```lua
function LandEdgeFinder.PrecomputeValidPositions(world, min_distance)
    -- ... 现有代码 ...
    
    for y = 0, map_height - 1 do
        for x = 0, map_width - 1 do
            local tile = world:GetTile(x, y)
            if tile and tile ~= 1 and TileGroupManager:IsLandTile(tile) and not TileGroupManager:IsOceanTile(tile) then
                local dist_to_edge = DistanceToEdge(x, y, world, 20, 0)
                
                if dist_to_edge >= min_distance then
                    local world_x, world_y = TileToWorldCoords(x, y, map_width, map_height)
                    table.insert(VALID_POSITIONS, {
                        tx = x,
                        ty = y,
                        world_x = world_x,
                        world_y = world_y
                    })
                    valid_count = valid_count + 1
                    
                    -- 替换为木板地皮
                    world:SetTile(x, y, WORLD_TILES.WOODFLOOR)
                end
            end
        end
    end
    
    print(string.format(
        "[Move Entity V2] [LandEdgeFinder] 预计算完成: 检查了 %d 个 tiles, 找到 %d 个合法坐标, 已替换 %d 个 tile 为木板地皮",
        checked_count, valid_count, valid_count
    ))
    
    -- ... 其余代码 ...
end
```

#### 方案 2: 在预计算完成后批量替换

在 `PrecomputeValidPositions` 完成后，遍历 `VALID_POSITIONS` 并替换所有地皮。

**优点**:
- 逻辑分离：预计算和地皮替换分开
- 易于控制：可以选择性地替换（例如，只替换部分坐标）

**缺点**:
- 需要遍历两次：一次预计算，一次替换
- 如果 `VALID_POSITIONS` 被修改，可能不一致

**实现步骤**:
1. 在 `LandEdgeFinder` 中添加新函数 `ReplaceValidPositionsWithWoodFloor(world)`
2. 遍历 `VALID_POSITIONS`，对每个坐标调用 `world:SetTile(x, y, WORLD_TILES.WOODFLOOR)`
3. 在 `PrecomputeValidPositions` 完成后调用此函数

**代码示例**:
```lua
function LandEdgeFinder.ReplaceValidPositionsWithWoodFloor(world)
    if not world then
        print("[Move Entity V2] ⚠️  无法替换地皮：world 对象为空")
        return 0
    end
    
    local replaced_count = 0
    for _, pos in ipairs(VALID_POSITIONS) do
        local current_tile = world:GetTile(pos.tx, pos.ty)
        -- 确保是陆地 tile（防止在替换过程中 tile 被修改）
        if current_tile and current_tile ~= 1 and TileGroupManager:IsLandTile(current_tile) and not TileGroupManager:IsOceanTile(current_tile) then
            world:SetTile(pos.tx, pos.ty, WORLD_TILES.WOODFLOOR)
            replaced_count = replaced_count + 1
        end
    end
    
    print(string.format(
        "[Move Entity V2] [LandEdgeFinder] 已替换 %d 个有效坐标的地皮为木板地皮",
        replaced_count
    ))
    
    return replaced_count
end
```

#### 方案 3: 在布局放置时替换

在 `FindNearestValidPosition` 找到有效坐标后，立即替换该坐标的地皮。

**优点**:
- 按需替换：只替换实际使用的坐标
- 节省资源：不替换未使用的有效坐标

**缺点**:
- 时机较晚：在布局放置时才替换，可能影响视觉效果
- 逻辑分散：替换逻辑分散在多个地方

### 注意事项

1. **时机选择**:
   - 必须在世界生成阶段（`modworldgenmain.lua`）进行
   - 建议在预计算完成后立即替换，确保所有有效坐标都被处理

2. **Tile 验证**:
   - 替换前应验证 tile 仍然是有效的陆地 tile
   - 防止在世界生成过程中 tile 被修改（如变成 IMPASSABLE 或 OCEAN）

3. **性能考虑**:
   - 如果有效坐标很多（如 18915 个），批量替换可能需要一些时间
   - 建议添加进度日志，显示替换进度

4. **视觉效果**:
   - 木板地皮在游戏中是可见的，玩家可以清楚地看到哪些区域是"安全区域"
   - 如果不想让玩家看到，可以考虑使用其他 tile 类型（如 `WORLD_TILES.ROAD`）

5. **兼容性**:
   - 确保 `WORLD_TILES.WOODFLOOR` 在所有游戏版本中都可用
   - 如果不可用，可以使用 `WORLD_TILES.ROAD` 作为替代

### 实现建议

**推荐使用方案 1（在预计算时立即替换）**:

1. **修改 `PrecomputeValidPositions` 函数**:
   - 在找到有效坐标并添加到 `VALID_POSITIONS` 后，立即调用 `world:SetTile(x, y, WORLD_TILES.WOODFLOOR)`
   - 添加替换计数，在日志中显示替换了多少个 tile

2. **添加验证**:
   - 替换前检查 tile 是否仍然是有效的陆地 tile
   - 如果 tile 已被修改，跳过替换并记录警告

3. **添加配置选项**（可选）:
   - 在 `modinfo.lua` 或配置文件中添加选项，允许玩家选择是否替换地皮
   - 或者选择替换为哪种地皮类型

### 待实现

- [ ] 在 `PrecomputeValidPositions` 中添加地皮替换逻辑
- [ ] 添加替换计数和日志记录
- [ ] 添加 tile 验证，确保只替换有效的陆地 tile
- [ ] 测试替换效果，确保所有有效坐标都被正确替换
- [ ] 考虑添加配置选项，允许玩家自定义地皮类型

---

## 调研：检测世界生成重试

### 需求描述

在每次世界生成重试时打印日志，用于调试和追踪世界生成过程。

### 世界生成重试机制

**源码位置**: `src/worldgen_main.lua:418-439`

**重试流程**:
```lua
local try = 1
local maxtries = 5

while savedata == nil do
    savedata = forest_map.Generate(...)
    
    if savedata == nil then
        if try >= maxtries then
            print("An error occured during world and we give up! [was ",try," of ",maxtries,"]")
            return nil
        else
            print("An error occured during world gen we will retry! [was ",try," of ",maxtries,"]")
        end
        try = try + 1
        collectgarbage("collect")
        WorldSim:ResetAll()  -- 重置世界状态
    end
end
```

**关键发现**:
1. 每次重试时，`modworldgenmain.lua` 会被重新执行（`src/mods.lua:577`）
2. 重试时会调用 `WorldSim:ResetAll()` 重置世界状态
3. 游戏本身会在日志中打印重试消息：`"An error occured during world gen we will retry! [was X of 5]"`

### 检测方案

#### 方案 1: 使用模块级变量记录调用次数（推荐）⭐

**原理**:
- `modworldgenmain.lua` 在每次重试时都会被重新执行
- 使用模块级变量记录 `modworldgenmain.lua` 的执行次数
- 每次执行时检查是否是重试（执行次数 > 1）

**优点**:
- 简单可靠：不依赖 Hook，直接利用模块加载机制
- 准确：每次重试都会重新加载模块，计数准确
- 无副作用：不影响游戏原有逻辑

**缺点**:
- 无法区分第一次生成和重试（都需要记录）

**实现步骤**:
1. 在 `modworldgenmain.lua` 中使用模块级变量记录执行次数
2. 每次执行时检查计数，如果 > 1 则打印重试日志
3. 可选：记录每次执行的时间戳，便于追踪

**代码示例**:
```lua
-- modworldgenmain.lua
local world_gen_attempt = (world_gen_attempt or 0) + 1

if world_gen_attempt > 1 then
    print(string.format(
        "[Move Entity V2] 🔄 检测到世界生成重试: 第 %d 次尝试",
        world_gen_attempt
    ))
else
    print("[Move Entity V2] 🌍 开始世界生成: 第 1 次尝试")
end

-- ... 其余代码 ...
```

**注意事项**:
- 模块级变量在 Lua 中需要使用全局变量或 `package.loaded` 来持久化
- 如果使用局部变量，每次模块重新加载时都会重置

#### 方案 2: Hook WorldSim:ResetAll()

**原理**:
- Hook `WorldSim:ResetAll()` 方法
- 每次调用时打印重试日志

**优点**:
- 直接检测重试操作
- 可以获取更多上下文信息

**缺点**:
- `ResetAll()` 可能在其他地方也被调用，需要区分
- 需要确保 Hook 时机正确（在 `WorldSim` 加载后）
- 可能影响性能

**实现步骤**:
1. 在 `modworldgenmain.lua` 中 Hook `WorldSim:ResetAll()`
2. 在 Hook 函数中检查调用栈或上下文，确认是世界生成重试
3. 打印重试日志

**代码示例**:
```lua
-- modworldgenmain.lua
local original_ResetAll = WorldSim.ResetAll
local reset_count = 0

WorldSim.ResetAll = function(self, ...)
    reset_count = reset_count + 1
    if reset_count > 0 then
        print(string.format(
            "[Move Entity V2] 🔄 检测到 WorldSim:ResetAll() 调用: 第 %d 次（可能是世界生成重试）",
            reset_count
        ))
    end
    return original_ResetAll(self, ...)
end
```

**注意事项**:
- `ResetAll()` 可能在其他场景也被调用（如世界重置）
- 需要结合其他信息（如 `modworldgenmain.lua` 的执行次数）来确认是重试

#### 方案 3: 监听日志消息

**原理**:
- Hook `print` 函数，监听重试消息
- 当检测到 `"An error occured during world gen we will retry!"` 时打印日志

**优点**:
- 直接检测游戏的重试消息
- 可以获取重试次数信息

**缺点**:
- 不够可靠：依赖日志消息格式，可能因版本变化而失效
- 性能开销：需要 Hook `print` 函数，可能影响性能
- 实现复杂：需要解析日志消息

**不推荐使用此方案**

### 推荐实现

**推荐使用方案 1（模块级变量记录调用次数）**:

1. **实现简单**: 只需在 `modworldgenmain.lua` 开头添加几行代码
2. **可靠性高**: 不依赖 Hook，利用模块加载机制
3. **无副作用**: 不影响游戏原有逻辑

**实现代码**:
```lua
-- modworldgenmain.lua
-- 使用全局变量记录执行次数（在模块重新加载时保持）
_G.move_entity_v2_world_gen_attempt = (_G.move_entity_v2_world_gen_attempt or 0) + 1
local attempt = _G.move_entity_v2_world_gen_attempt

if attempt > 1 then
    print(string.format(
        "[Move Entity V2] 🔄 检测到世界生成重试: 第 %d 次尝试",
        attempt
    ))
else
    print("[Move Entity V2] 🌍 开始世界生成: 第 1 次尝试")
end

-- ... 其余代码 ...
```

**可选增强**:
- 记录每次尝试的时间戳
- 记录重试原因（如果可以从日志中获取）
- 在重试时重置某些状态（如 `VALID_POSITIONS`）

### 相关文件

- `src/worldgen_main.lua:418-439` - 世界生成重试机制
- `src/mods.lua:577` - modworldgenmain.lua 加载逻辑
- `mods/move-entity-v2/modworldgenmain.lua` - Mod 入口文件

---

## 调研：主要建筑之间最小距离限制

### 需求描述

将 `SPECIAL_LAYOUTS` 和 `SPECIAL_PREFABS` 统称为"主要建筑"，要求主要建筑彼此之间的距离不能小于 8 tiles。

**主要建筑列表**:
- **SPECIAL_LAYOUTS**: `DefaultPigking`, `DragonflyArena`, `MoonbaseOne`, `Charlie1`, `Charlie2`, `Oasis`, `junk_yard`
- **SPECIAL_PREFABS**: `multiplayer_portal`, `beequeenhive`

### 问题分析

当前实现中，每个主要建筑在放置时只考虑了：
1. 距离边缘 >= 6 tiles（通过 `PrecomputeValidPositions` 和 `FindNearestValidPosition`）
2. 没有考虑与其他已放置的主要建筑之间的距离

这可能导致：
- 多个主要建筑被放置在相近的位置（距离 < 8 tiles）
- 新放置的主要建筑可能靠近已放置的主要建筑

### 实现方案

#### 方案 1: 维护已放置建筑列表 + 实时距离检查 ⭐ **推荐**

**思路**:
1. 创建一个全局的已放置主要建筑位置列表 `PLACED_MAJOR_BUILDINGS`
2. 在 `PigkingHandler.ProcessPosition` 和 `PrefabHandler.ProcessPrefabPosition` 中：
   - 查找合法位置时，检查候选位置与所有已放置建筑的距离 >= 8 tiles
   - 找到合法位置后，将新建筑的位置添加到 `PLACED_MAJOR_BUILDINGS`
3. 在 `FindNearestValidPosition` 中增加距离检查逻辑

**优点**:
- 逻辑清晰，易于理解和维护
- 可以灵活处理放置顺序
- 不需要修改预计算逻辑
- 可以记录每个建筑的类型和名称，便于调试

**缺点**:
- 每次查找都需要遍历所有已放置的建筑，如果建筑数量多可能影响性能
- 需要确保在查找时能访问到已放置建筑列表

**实现步骤**:
1. 在 `land_edge_finder.lua` 中：
   - 添加 `PLACED_MAJOR_BUILDINGS` 全局列表
   - 添加 `AddPlacedBuilding(type, name, tile_x, tile_y, world_x, world_y)` 函数
   - 添加 `ClearPlacedBuildings()` 函数（用于世界生成重试时清空）
   - 修改 `FindNearestValidPosition`，增加与已放置建筑的距离检查
2. 在 `pigking_handler.lua` 中：
   - 在 `ProcessPosition` 找到合法位置后，调用 `AddPlacedBuilding("layout", layout_name, new_tx, new_ty, new_world_x, new_world_y)`
3. 在 `prefab_handler.lua` 中：
   - 在 `ProcessPrefabPosition` 找到合法位置后，调用 `AddPlacedBuilding("prefab", prefab, new_tile_x, new_tile_y, new_world_x, new_world_y)`
4. 在 `layout_hook.lua` 中：
   - 在 `InstallLayoutHook` 开始时调用 `ClearPlacedBuildings()`（确保每次世界生成重试时清空）

#### 方案 2: 动态更新合法坐标集合

**思路**:
1. 在预计算时，只考虑距离边缘 >= 6 tiles 的坐标
2. 当放置一个主要建筑后，从 `VALID_POSITIONS` 中移除距离该位置 < 8 tiles 的坐标
3. 后续查找时，自动排除这些已被占用的区域

**优点**:
- 性能好，不需要在每次查找时重新计算
- 逻辑清晰，逐步缩小可用区域

**缺点**:
- 如果放置顺序不当，可能导致后续建筑找不到合法位置
- 需要确保在放置后立即更新 `VALID_POSITIONS`

**实现步骤**:
1. 在 `LandEdgeFinder` 中添加 `RemovePositionsNearby(tile_x, tile_y, min_distance)` 函数
2. 在 `PigkingHandler.ProcessPosition` 中，放置 layout 后调用该函数（min_distance = 8）
3. 在 `PrefabHandler.ProcessPrefabPosition` 中，放置 prefab 后调用该函数（min_distance = 8）

#### 方案 3: 混合方案

**思路**:
1. 预计算时只考虑距离边缘 >= 6 tiles
2. 在查找时，实时检查：
   - 距离边缘 >= 6 tiles
   - 距离所有已放置的主要建筑 >= 8 tiles
3. 如果找到合法位置，放置后更新 `VALID_POSITIONS`（移除附近坐标）

**优点**:
- 结合两种方案的优点
- 性能较好，逻辑清晰

**缺点**:
- 实现稍复杂

### 距离计算

**Tile 坐标距离（欧几里得距离）**:
```lua
local function TileDistance(tile_x1, tile_y1, tile_x2, tile_y2)
    local dx = tile_x1 - tile_x2
    local dy = tile_y1 - tile_y2
    return math.sqrt(dx * dx + dy * dy)
end
```

**世界坐标距离（转换为 tile 单位）**:
```lua
local TILE_SCALE = 4
local function WorldDistance(world_x1, world_y1, world_x2, world_y2)
    local dx = world_x1 - world_x2
    local dy = world_y1 - world_y2
    return math.sqrt(dx * dx + dy * dy) / TILE_SCALE  -- 转换为 tile 单位
end
```

**注意**: 由于主要建筑可能使用不同的坐标系统（layout 使用 tile 坐标，prefab 使用 tile 坐标），建议统一使用 tile 坐标进行距离计算。

### 已放置建筑位置记录

需要记录的信息：
- 建筑类型（"layout" 或 "prefab"）
- 建筑名称（用于日志和调试）
- 最终放置的 tile 坐标 (tile_x, tile_y)
- 对应的世界坐标 (world_x, world_y)（可选，用于调试）

**数据结构**:
```lua
local PLACED_MAJOR_BUILDINGS = {
    {
        type = "layout",  -- 或 "prefab"
        name = "DefaultPigking",
        tile_x = 276,
        tile_y = 270,
        world_x = 254.00,  -- 可选
        world_y = 230.00   -- 可选
    },
    {
        type = "prefab",
        name = "multiplayer_portal",
        tile_x = 200,
        tile_y = 250,
        world_x = 100.00,
        world_y = 200.00
    },
    -- ...
}
```

### 查找逻辑修改

在 `FindNearestValidPosition` 中，需要增加对已放置建筑的距离检查：

```lua
function LandEdgeFinder.FindNearestValidPosition(world_x, world_y, world, max_radius)
    -- ... 现有逻辑 ...
    
    -- 将世界坐标转换为 tile 坐标
    local start_tx, start_ty = WorldToTileCoords(world_x, world_y, map_width, map_height)
    
    -- 螺旋搜索：从内到外，逐层搜索
    for radius = 0, max_radius do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.abs(dx) == radius or math.abs(dy) == radius then
                    local tx, ty = start_tx + dx, start_ty + dy
                    
                    -- 边界检查
                    if tx >= 0 and tx < map_width and ty >= 0 and ty < map_height then
                        -- 检查是否是合法位置（距离边缘 >= 6 tiles）
                        local tile = world:GetTile(tx, ty)
                        if tile and tile ~= 1 and TileGroupManager:IsLandTile(tile) and not TileGroupManager:IsOceanTile(tile) then
                            local dist_to_edge = DistanceToEdge(tx, ty, world, 20, 0)
                            
                            if dist_to_edge >= 6 then
                                -- 检查距离所有已放置的主要建筑 >= 8 tiles
                                local too_close = false
                                for _, building in ipairs(PLACED_MAJOR_BUILDINGS) do
                                    local dist = TileDistance(tx, ty, building.tile_x, building.tile_y)
                                    if dist < 8 then
                                        too_close = true
                                        break
                                    end
                                end
                                
                                if not too_close then
                                    -- 找到合法位置
                                    local new_world_x, new_world_y = TileToWorldCoords(tx, ty, map_width, map_height)
                                    return new_world_x, new_world_y, true
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    return world_x, world_y, false
end
```

### 放置顺序考虑

**问题**: 如果多个主要建筑需要移动，放置顺序可能影响结果。

**分析**:
- Layout 和 Prefab 的放置顺序由游戏世界生成流程决定
- Layout 通过 `obj_layout.Convert` Hook 处理，Prefab 通过 `PopulateWorld_AddEntity` Hook 处理
- 需要确认这两个 Hook 的执行顺序

**建议**:
- 如果某个建筑找不到满足距离要求的位置（距离边缘 >= 6 且距离其他建筑 >= 8），可以：
  1. 使用原始坐标（不移动）
  2. 放宽距离要求（例如只检查距离边缘 >= 6，不检查与其他建筑的距离）
  3. 记录警告日志，提示用户

### 坐标系统统一

**当前情况**:
- Layout 使用 tile 坐标（`ReserveSpace` 返回 tile 坐标，`ReserveAndPlaceLayout` 的 `position` 参数需要 tile 坐标）
- Prefab 使用 tile 坐标（`PopulateWorld_AddEntity` 的参数是 tile 坐标）

**建议**:
- 统一使用 tile 坐标进行距离计算和存储
- 在需要时转换为世界坐标（例如用于日志输出）

### 性能考虑

1. **已放置建筑数量**: 如果主要建筑数量不多（< 10），实时距离检查的性能影响可以忽略
2. **查找范围**: `FindNearestValidPosition` 使用螺旋搜索，最大半径 20 tiles，如果已放置建筑较多，可能需要优化
3. **优化建议**:
   - 如果已放置建筑数量 > 20，可以考虑使用空间索引（如网格索引）来加速距离检查
   - 或者限制搜索范围，只检查已放置建筑附近的区域

### 实现建议

**推荐使用方案 1（维护已放置建筑列表 + 实时距离检查）**:

1. **在 `land_edge_finder.lua` 中添加**:
   ```lua
   -- 已放置的主要建筑列表
   local PLACED_MAJOR_BUILDINGS = {}
   
   -- 添加已放置的建筑
   function LandEdgeFinder.AddPlacedBuilding(type, name, tile_x, tile_y, world_x, world_y)
       table.insert(PLACED_MAJOR_BUILDINGS, {
           type = type,
           name = name,
           tile_x = tile_x,
           tile_y = tile_y,
           world_x = world_x,
           world_y = world_y
       })
       print(string.format(
           "[Move Entity V2] [LandEdgeFinder] 已记录主要建筑: %s '%s' at tile (%d, %d)",
           type, name, tile_x, tile_y
       ))
   end
   
   -- 清空已放置建筑列表（用于世界生成重试）
   function LandEdgeFinder.ClearPlacedBuildings()
       PLACED_MAJOR_BUILDINGS = {}
       print("[Move Entity V2] [LandEdgeFinder] 已清空已放置建筑列表")
   end
   
   -- 获取已放置建筑数量
   function LandEdgeFinder.GetPlacedBuildingsCount()
       return #PLACED_MAJOR_BUILDINGS
   end
   ```

2. **修改 `FindNearestValidPosition`**: 增加与已放置建筑的距离检查（见上面的代码示例）

3. **在 `pigking_handler.lua` 中调用**:
   ```lua
   if found_valid then
       -- 将世界坐标转换回 tile 坐标
       new_tx, new_ty = LandEdgeFinder.WorldToTileCoords(new_world_x, new_world_y, map_width, map_height)
       
       -- 记录已放置的建筑
       LandEdgeFinder.AddPlacedBuilding("layout", layout_name, new_tx, new_ty, new_world_x, new_world_y)
       
       found_valid = true
       -- ... 其余代码 ...
   end
   ```

4. **在 `prefab_handler.lua` 中调用**:
   ```lua
   if found_valid then
       -- 转换回 tile 坐标
       local new_tile_x, new_tile_y = WorldToTileCoords(new_world_x, new_world_y, width, height)
       
       -- 记录已放置的建筑
       LandEdgeFinder.AddPlacedBuilding("prefab", prefab, new_tile_x, new_tile_y, new_world_x, new_world_y)
       
       -- ... 其余代码 ...
   end
   ```

5. **在 `layout_hook.lua` 中调用**:
   ```lua
   local function InstallLayoutHook()
       -- ... 现有代码 ...
       
       local LandEdgeFinder = require("land_edge_finder")
       LandEdgeFinder.ClearValidPositions()  -- 现有代码
       LandEdgeFinder.ClearPlacedBuildings()  -- 新增：清空已放置建筑列表
       
       -- ... 其余代码 ...
   end
   ```

### 注意事项

1. **世界生成重试**: 确保在每次世界生成重试时清空 `PLACED_MAJOR_BUILDINGS`（在 `InstallLayoutHook` 开始时调用 `ClearPlacedBuildings()`）

2. **找不到合法位置**: 如果某个建筑找不到满足距离要求的位置，应该：
   - 记录警告日志
   - 使用原始坐标（不移动）或只满足距离边缘 >= 6 的位置

3. **距离计算精度**: 使用欧几里得距离（`sqrt(dx² + dy²)`），确保距离计算准确

4. **边界情况**: 如果地图较小或主要建筑数量较多，可能无法满足所有距离要求，需要处理这种情况

5. **调试支持**: 添加详细的日志输出，记录每个建筑的放置位置和与其他建筑的距离

### 待实现

- [ ] 在 `LandEdgeFinder` 中添加 `PLACED_MAJOR_BUILDINGS` 列表和相关函数
- [ ] 修改 `FindNearestValidPosition`，增加与已放置建筑的距离检查
- [ ] 在 `PigkingHandler.ProcessPosition` 中调用 `AddPlacedBuilding`
- [ ] 在 `PrefabHandler.ProcessPrefabPosition` 中调用 `AddPlacedBuilding`
- [ ] 在 `InstallLayoutHook` 中调用 `ClearPlacedBuildings`
- [ ] 添加日志记录，显示每个建筑的放置位置和与其他建筑的距离
- [ ] 测试多个主要建筑的放置顺序和距离检查

---

## 调研：主世界和子世界（Shard）系统

### 需求描述

了解 Don't Starve Together 中的主世界和子世界（Shard）系统，以便理解为什么 `GlobalPostPopulate` 可能被多次调用。

### 关键发现

#### 1. Shard 系统概述

**Shard（分片）** 是 Don't Starve Together 中的多世界系统，允许服务器同时运行多个独立的世界：

- **主世界（Master Shard）**: 通常是地面世界（`location = "forest"`）
- **子世界（Secondary Shard）**: 通常是洞穴世界（`location = "cave"`）

**相关代码** (`src/prefabs/world.lua:426`):
```lua
inst.ismastersim = TheNet:GetIsMasterSimulation()
inst.ismastershard = inst.ismastersim and not TheShard:IsSecondary()
```

#### 2. 世界类型（Location）

**主要世界类型** (`src/map/locations.lua`):
- `"forest"`: 地面世界（主世界）
- `"cave"`: 洞穴世界（子世界）
- `"lavaarena"`: 熔岩竞技场
- `"quagmire"`: 沼泽

**世界生成流程** (`src/worldgen_main.lua:387-392`):
```lua
local level = Level(world_gen_data.level_data)
local prefab = level.location  -- "forest" 或 "cave"
savedata = forest_map.Generate(prefab, max_map_width, max_map_height, choose_tasks, level, world_gen_data.level_type)
```

#### 3. 多世界生成机制

**世界生成顺序**:
1. 主世界（forest）先生成
2. 子世界（cave）后生成（如果启用）
3. 每个世界都有独立的 `WorldSim` 实例
4. 每个世界都有独立的 `Graph` 实例和 `topology_save.root`

**相关代码** (`src/map/forest_map.lua:887`):
```lua
topology_save.root:GlobalPostPopulate(entities, map_width, map_height)
```

**关键发现**:
- 每个世界（主世界和子世界）都会调用自己的 `GlobalPostPopulate`
- 每个世界都有独立的 `Graph` 实例，`self.parent == nil` 对于每个世界的根节点都成立
- 因此，如果服务器启用了洞穴，`GlobalPostPopulate` 会被调用两次：
  1. 主世界（forest）生成完成后
  2. 洞穴世界（cave）生成完成后

#### 4. Shard 连接机制

**Shard 网络** (`src/shardnetworking.lua`):
- `Shard_GetConnectedShards()`: 获取所有连接的 shard
- `TheShard:IsMaster()`: 检查是否是主 shard
- `TheShard:IsSecondary()`: 检查是否是次 shard

**世界数据同步** (`src/networking.lua:788-794`):
```lua
if TheShard:IsMaster() then
    -- Merge secondary shard worldgen data
    for k, v in pairs(Shard_GetConnectedShards()) do
        if v.world ~= nil and v.world[1] ~= nil then
            table.insert(clusteroptions, v.world[1])
        end
    end
end
```

#### 5. Mod 世界生成入口

**`modworldgenmain.lua` 的执行时机**:
- 每个世界生成时，`modworldgenmain.lua` 都会被重新执行
- 主世界生成时执行一次
- 洞穴世界生成时再执行一次（如果启用）

**相关代码** (`src/mods.lua:577`):
```lua
self:InitializeModMain(modname, mod, "modworldgenmain.lua")
```

### 对地皮替换的影响

**问题**:
- 如果服务器启用了洞穴，`GlobalPostPopulate` 会被调用两次：
  1. 主世界生成完成后 → 地皮替换执行
  2. 洞穴世界生成完成后 → 地皮替换再次执行（使用主世界的 `VALID_POSITIONS`）

**原因**:
- `VALID_POSITIONS` 是模块级变量，在主世界生成时被计算
- 洞穴世界生成时，`VALID_POSITIONS` 仍然包含主世界的数据
- 洞穴世界调用 `GlobalPostPopulate` 时，使用了主世界的 `VALID_POSITIONS`，导致地皮替换在错误的世界执行

**解决方案**:
1. **检查世界类型**: 在 `GlobalPostPopulate` Hook 中检查当前世界类型，只对主世界（forest）执行地皮替换
2. **使用全局标记**: 使用全局变量标记是否已执行地皮替换，防止重复执行
3. **每次执行前清空**: 在每次 `GlobalPostPopulate` 执行前清空 `VALID_POSITIONS`，确保使用正确的世界数据

### 验证方法

**添加调试日志**:
```lua
Graph.GlobalPostPopulate = function(self, entities, width, height)
    local result = original_GlobalPostPopulate(self, entities, width, height)
    
    if self.parent == nil then
        -- 检查当前世界类型
        local world_prefab = WorldSim and WorldSim:GetWorldPrefab() or "unknown"
        print(string.format(
            "[Move Entity V2] [TurfReplacerHook] GlobalPostPopulate called: world_prefab = %s, self.id = %s",
            world_prefab, tostring(self.id)
        ))
        
        -- 只对主世界（forest）执行地皮替换
        if world_prefab == "forest" then
            -- ... 执行地皮替换 ...
        end
    end
    
    return result
end
```

### 相关文件

- `src/map/locations.lua` - 世界类型定义
- `src/map/forest_map.lua:887` - `GlobalPostPopulate` 调用位置
- `src/map/network.lua:770` - `Graph:GlobalPostPopulate` 实现
- `src/prefabs/world.lua:426` - Shard 判断逻辑
- `src/shardnetworking.lua` - Shard 网络管理
- `src/mods.lua:577` - Mod 世界生成入口

### 待实现

- [ ] 在 `GlobalPostPopulate` Hook 中添加世界类型检查
- [ ] 只对主世界（forest）执行地皮替换
- [ ] 添加调试日志，记录每次 `GlobalPostPopulate` 调用的世界类型
- [ ] 测试启用洞穴时的地皮替换行为

---

## 调研：世界生成重试时 modworldgenmain.lua 的执行情况

### 需求描述

确认每次世界生成重试时，`modworldgenmain.lua` 是否会被重新执行。

### 源码分析

#### 1. 世界生成重试机制

**重试循环** (`src/worldgen_main.lua:418-439`):
```lua
local try = 1
local maxtries = 5

while savedata == nil do
    savedata = forest_map.Generate(prefab, max_map_width, max_map_height, choose_tasks, level, world_gen_data.level_type)
    
    if savedata == nil then
        if try >= maxtries then
            print("An error occured during world and we give up! [was ",try," of ",maxtries,"]")
            return nil
        else
            print("An error occured during world gen we will retry! [was ",try," of ",maxtries,"]")
        end
        try = try + 1
        collectgarbage("collect")
        WorldSim:ResetAll()  -- 重置世界状态
    elseif GEN_PARAMETERS == "" or world_gen_data.show_debug == true then
        ShowDebug(savedata)
    end
end
```

**关键发现**:
- 重试循环在 `GenerateNew` 函数内部
- 每次重试时调用 `WorldSim:ResetAll()` 重置世界状态
- 但**没有重新调用** `ModManager:LoadMods(true)`

#### 2. Mod 加载时机

**Mod 加载** (`src/worldgen_main.lua:144-148`):
```lua
local moddata = json.decode(GEN_MODDATA)
if moddata then
    KnownModIndex:RestoreCachedSaveData(moddata.index)
    ModManager:LoadMods(true)  -- 只在这里调用一次
end
```

**关键发现**:
- `ModManager:LoadMods(true)` 只在 `worldgen_main.lua` 文件开始处调用一次
- 调用位置在 `GenerateNew` 函数**之前**
- 重试循环在 `GenerateNew` 函数**内部**，因此不会重新调用 `LoadMods`

#### 3. modworldgenmain.lua 的执行流程

**Mod 初始化** (`src/mods.lua:577-583`):
```lua
for i,mod in ipairs(self.mods) do
    -- ... 设置 package.path 等 ...
    
    self.currentlyloadingmod = mod.modname
    self:InitializeModMain(mod.modname, mod, "modworldgenmain.lua")
    -- ...
end
```

**InitializeModMain 实现** (`src/mods.lua:587-618`):
```lua
function ModWrangler:InitializeModMain(modname, env, mainfile, safe)
    -- ...
    local fn = kleiloadlua(MODS_ROOT..modname.."/"..mainfile)  -- 加载文件
    -- ...
    if safe then
        status, r = RunInEnvironmentSafe(fn,env)  -- 执行函数
    else
        status, r = RunInEnvironment(fn,env)  -- 执行函数
    end
    -- ...
end
```

**关键发现**:
- `kleiloadlua` 加载文件并返回函数
- `RunInEnvironment` 执行该函数
- 但是，`kleiloadlua` 可能使用缓存，不会每次都重新加载文件
- 即使重新加载，`RunInEnvironment` 也只是执行函数，**不会重新执行模块级的代码**（如 `print` 语句）

### 结论

**`modworldgenmain.lua` 只会在世界生成开始前加载和执行一次，不会在每次重试时重新执行。**

**原因**:
1. `ModManager:LoadMods(true)` 只在 `worldgen_main.lua` 开始时调用一次
2. 重试循环在 `GenerateNew` 函数内部，不会重新调用 `LoadMods`
3. 即使 `kleiloadlua` 重新加载文件，模块级的代码（如 `print` 语句）也不会重新执行

**影响**:
- 模块级变量（如 `VALID_POSITIONS`）在重试时不会被重置
- 模块级的 `print` 语句（如 `print("[Move Entity V2] 🔄 检测到世界生成")`）不会在重试时重新执行
- Hook 安装代码（如 `InstallLayoutHook()`）不会在重试时重新执行

### 解决方案

#### 方案 1: Hook `WorldSim:ResetAll()` + 修改 `layout_hook.lua` 中的预计算逻辑 ⭐ **推荐**

**思路**:
1. Hook `WorldSim:ResetAll()` 来检测世界生成重试，清空 `VALID_POSITIONS` 并重置 `precomputed` 标记
2. 修改 `layout_hook.lua` 中的预计算逻辑：
   - 不依赖 `precomputed` 局部变量（因为它在重试时不会重置）
   - 改为检查 `VALID_POSITIONS` 是否为空，如果为空则重新预计算
   - 这样即使重试时 `precomputed` 仍然是 `true`，也能重新预计算

**优点**:
- 准确检测世界生成重试
- 确保每次使用正确的世界数据
- 不需要修改 `GlobalPostPopulate` 的逻辑
- 预计算逻辑更健壮

**实现步骤**:

1. **在 `modworldgenmain.lua` 中 Hook `WorldSim:ResetAll()`**:
```lua
-- modworldgenmain.lua
print("[Move Entity V2] 🔄 检测到世界生成")

-- Hook WorldSim:ResetAll() 来检测世界生成重试
local LandEdgeFinder = require("land_edge_finder")
local original_ResetAll = WorldSim.ResetAll
WorldSim.ResetAll = function(self, ...)
    -- 清空 VALID_POSITIONS，准备重新计算
    LandEdgeFinder.ClearValidPositions()
    print("[Move Entity V2] 🔄 检测到世界生成重试，已清空 VALID_POSITIONS")
    
    -- 重置地皮替换标记
    _G.move_entity_v2_turf_replaced = false
    
    return original_ResetAll(self, ...)
end

-- ... 其余代码 ...
```

2. **修改 `layout_hook.lua` 中的预计算逻辑**:
```lua
-- layout_hook.lua
obj_layout.Convert = function(node_id, item, addEntity)
    -- 检查 VALID_POSITIONS 是否为空，如果为空则重新预计算
    -- 不依赖 precomputed 局部变量，因为它在重试时不会重置
    if LandEdgeFinder.GetValidPositionsCount() == 0 then
        local world = WorldSim
        if world then
            local map_width, map_height = world:GetWorldSize()
            if map_width and map_height then
                print("[Move Entity V2] [LayoutHook] 开始预计算合法坐标（距离边缘 >= 6 tiles）...")
                local valid_count = LandEdgeFinder.PrecomputeValidPositions(world, 6)
                if valid_count > 0 then
                    print(string.format("[Move Entity V2] [LayoutHook] 预计算完成，找到 %d 个合法坐标", valid_count))
                else
                    print("[Move Entity V2] ⚠️  预计算未找到合法坐标，将使用原始坐标")
                end
            else
                print("[Move Entity V2] ⚠️  无法获取地图尺寸，跳过预计算")
            end
        end
    end
    
    -- ... 其余代码 ...
end
```

#### 方案 2: 在 `GlobalPostPopulate` 中检查并清空（简化版）

**思路**:
- 在每次 `GlobalPostPopulate` 执行时：
  1. 检查世界类型，只对主世界执行
  2. 清空 `VALID_POSITIONS` 并重新预计算
  3. 使用全局标记防止重复执行

**优点**:
- 实现简单
- 不需要 Hook `WorldSim:ResetAll()`

**缺点**:
- 每次 `GlobalPostPopulate` 都会重新预计算，性能稍差
- 需要准确判断世界类型

**实现代码**:
```lua
-- turf_replacer_hook.lua
Graph.GlobalPostPopulate = function(self, entities, width, height)
    local result = original_GlobalPostPopulate(self, entities, width, height)
    
    if self.parent == nil and not (_G.move_entity_v2_turf_replaced) then
        -- 检查世界类型（简化：通过检查是否有海洋）
        local is_forest = false
        if WorldSim then
            local map_width, map_height = WorldSim:GetWorldSize()
            if map_width and map_height then
                -- 检查是否有海洋 tile（主世界有，洞穴没有）
                for x = 0, math.min(20, map_width - 1) do
                    for y = 0, math.min(20, map_height - 1) do
                        local tile = WorldSim:GetTile(x, y)
                        if tile and TileGroupManager:IsOceanTile(tile) then
                            is_forest = true
                            break
                        end
                    end
                    if is_forest then break end
                end
            end
        end
        
        if is_forest then
            -- 清空并重新预计算
            LandEdgeFinder.ClearValidPositions()
            LandEdgeFinder.PrecomputeValidPositions(WorldSim, 6)
            
            -- 执行地皮替换
            local valid_positions = LandEdgeFinder.GetValidPositions()
            if valid_positions and #valid_positions > 0 then
                TurfReplacer.ReplaceValidPositionsWithWoodFloor(WorldSim, valid_positions)
                _G.move_entity_v2_turf_replaced = true
            end
        end
    end
    
    return result
end
```

#### 方案 3: 使用 `obj_layout.Convert` 中的预计算时机

**思路**:
- 在 `obj_layout.Convert` Hook 中，每次预计算时检查是否是新的世界生成
- 使用全局变量记录上次预计算的世界 ID 或时间戳
- 如果检测到新的世界生成，清空 `VALID_POSITIONS`

**优点**:
- 利用现有的预计算机制
- 不需要额外的 Hook

**缺点**:
- 需要准确判断是否是新的世界生成
- 实现较复杂

#### 方案 4: 在 `layout_hook.lua` 中检测重试

**思路**:
- 在 `InstallLayoutHook` 中，使用全局变量记录调用次数
- 每次调用时检查是否是新的世界生成尝试
- 如果是，清空 `VALID_POSITIONS`

**实现代码**:
```lua
-- layout_hook.lua
local function InstallLayoutHook()
    -- 使用全局变量记录世界生成尝试次数
    _G.move_entity_v2_world_gen_attempt = (_G.move_entity_v2_world_gen_attempt or 0) + 1
    local attempt = _G.move_entity_v2_world_gen_attempt
    
    if attempt > 1 then
        print(string.format(
            "[Move Entity V2] 🔄 检测到世界生成重试: 第 %d 次尝试",
            attempt
        ))
    end
    
    local LandEdgeFinder = require("land_edge_finder")
    LandEdgeFinder.ClearValidPositions()  -- 每次调用都清空
    
    -- ... 其余代码 ...
end
```

### 推荐实现

**推荐使用方案 1（Hook `WorldSim:ResetAll()` + 在 `GlobalPostPopulate` 中检查世界类型）**:

**理由**:
1. **准确检测重试**: `WorldSim:ResetAll()` 在世界生成重试时会被调用，可以准确检测
2. **确保数据正确**: 通过检查 `VALID_POSITIONS` 是否为空来决定是否重新预计算，确保使用正确的世界数据
3. **逻辑更健壮**: 不依赖局部变量 `precomputed`，而是直接检查 `VALID_POSITIONS` 的状态

**实现要点**:
1. Hook `WorldSim:ResetAll()` 来清空 `VALID_POSITIONS` 和重置标记
2. 修改 `layout_hook.lua` 中的预计算逻辑，改为检查 `VALID_POSITIONS` 是否为空
3. 如果为空则重新预计算，确保使用当前世界的数据
4. 使用全局变量 `_G.move_entity_v2_turf_replaced` 防止地皮替换重复执行

### 待实现

- [ ] Hook `WorldSim:ResetAll()` 来检测重试并清空状态
- [ ] 修改 `layout_hook.lua` 中的预计算逻辑，改为检查 `VALID_POSITIONS` 是否为空
- [ ] 如果 `VALID_POSITIONS` 为空则重新预计算（使用当前世界的数据）
- [ ] 使用全局变量标记防止地皮替换重复执行
- [ ] 添加调试日志，记录每次调用的状态

### 相关文件

- `src/worldgen_main.lua:147` - `ModManager:LoadMods(true)` 调用位置
- `src/worldgen_main.lua:421-439` - 世界生成重试循环
- `src/mods.lua:577` - `modworldgenmain.lua` 的加载
- `src/mods.lua:587-618` - `InitializeModMain` 实现

---

