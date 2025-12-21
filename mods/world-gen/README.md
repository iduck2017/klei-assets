# World Gen Mod

## 功能

在世界生成时将猪王布景（包括猪王及其周围的所有相关实体和地板）移动到最近的海边位置。

## 使用方法

1. 将 `world-gen` 文件夹复制到 DST 的 mods 目录
2. 在游戏中启用此 mod
3. 创建新世界后，猪王布景将被移动到最近的海边

## 实现思路

### 整体架构

本mod采用模块化设计，将功能拆分为多个独立的脚本文件：

- `constants.lua`: 定义常量（实体类型、搜索半径等）
- `coast_detection.lua`: 海岸检测算法
- `layout_collection.lua`: 布局收集逻辑
- `pigking_mover.lua`: 移动逻辑
- `worldgen_hook.lua`: Hook入口点

### Hook点的选择

**为什么选择 `retrofit_savedata.DoRetrofitting`？**

1. **时机正确**: `DoRetrofitting` 在 `PopulateWorld` 阶段被调用，此时：
   - `TheWorld.Map` 已经初始化，可以访问tile数据
   - `savedata.ents` 已经包含所有实体的位置信息
   - 实体尚未实例化，修改位置不会造成视觉闪烁

2. **参数完整**: `DoRetrofitting(savedata, world_map)` 提供了：
   - `savedata`: 包含所有世界生成数据（实体、地图、拓扑等）
   - `world_map`: Map对象，可以检查tile类型和修改tile数据

3. **执行顺序**: 
   ```
   PopulateWorld()
   ├─ world.Map:SetFromString()  // 地图数据加载
   ├─ retrofit_savedata.DoRetrofitting(savedata, world_map)  // ← 我们的Hook点
   └─ worldentities.AddWorldEntities(savedata)  // 实体实例化
   ```

### 布局收集方法

**基于位置范围收集实体（与源码布局相似）**

不依赖布局定义文件，而是直接在猪王周围指定半径内收集所有相关实体：

1. **收集策略**: 
   ```lua
   -- 在猪王周围30单位半径内收集以下实体类型：
   -- pigking, insanityrock, sanityrock, pigtorch
   local entities = CollectEntitiesInRadius(savedata_ents, pigking_x, pigking_z, radius, entity_types)
   ```

2. **与源码布局的对比**:
   - **源码布局尺寸**：32x32 tiles（tilewidth=16），实际转换为8x8 tiles = 32x32单位
   - **最远实体距离**：根据源码，最远的insanityrock距离猪王中心约9单位
   - **我们的搜索半径**：30单位，完全覆盖整个布局（32单位对角线的一半约22.6单位）
   - **相似性**：✅ 覆盖范围与源码布局一致，能收集到所有相关实体
   - **差异**：❌ 不包含地板tile数据（只移动实体，不移动地板）

3. **优势**:
   - 不依赖布局定义文件（避免加载失败的问题）
   - 简单直接，基于实际位置匹配
   - 自动适应不同的布局变体（DefaultPigking、TorchPigking等）
   - 容错性好，即使布局略有变化也能收集到
   - 搜索半径30单位完全覆盖源码布局范围

4. **收集范围**:
   - 搜索半径：30单位（约7.5个tile，覆盖32x32单位的布局）
   - 实体类型：pigking, insanityrock, sanityrock, pigtorch
   - 保持相对位置：记录每个实体相对于猪王的偏移量

5. **地板tile收集**:
   - 在收集实体时，同时从map中读取猪王周围30单位半径内的所有tile
   - 记录每个tile的类型和位置（相对于猪王中心）
   - 移动到新位置时，将这些tile一起移动，保持相对位置不变

6. **注意事项**:
   - 30单位半径足够覆盖源码中所有实体（最远约9单位）和地板tile
   - 实体和地板都会一起移动，保持完整的布局

### 海岸检测算法

**同心圆搜索策略**

采用"由近到远"的同心圆搜索，找到第一个海岸位置就是最近的：

1. **海岸定义**: 
   - 必须是陆地tile（`map:IsLandTileAtPoint()`）
   - 周围8个方向中至少有一个是海洋tile（`map:IsOceanTileAtPoint()`）

2. **搜索策略**:
   ```
   从原始位置开始，按距离递增搜索：
   距离1: 16个方向，每2个tile检查一次
   距离2: 16个方向，每2个tile检查一次
   ...
   最大距离: 200单位（50个tile）
   ```

3. **优势**:
   - 保证找到的是最近的海岸
   - 搜索效率高（找到即返回）
   - 使用Map API，准确可靠

### 实体和地板移动

**实体移动**:
1. 计算位置偏移：`offset = new_position - original_position`
2. 遍历布局中的所有实体，保持相对位置不变
3. 直接修改 `savedata.ents` 中的坐标（修改引用，影响后续实例化）

**地板移动**:
1. **收集地板tile**：在收集实体时，同时从map中读取猪王周围30单位半径内的所有tile类型和位置
2. **记录相对位置**：记录每个tile相对于猪王中心的偏移量
3. **移动tile**：计算新位置后，使用 `map:SetTile()` 在新位置设置相同的tile类型，保持相对位置不变
4. **更新savedata**：更新 `savedata.map.tiles` 和 `savedata.map.nodeidtilemap`

### 关键技术点

1. **无备用方案**: 如果 `TheWorld.Map` 不可用，直接输出错误并返回原始位置，不使用不准确的拓扑方法

2. **模块通信**: 由于 `modimport` 不支持返回值，使用全局变量进行模块间通信：
   ```lua
   WorldGenMod_Constants = {...}
   WorldGenMod_CoastDetection = {...}
   ```

3. **容错处理**: 
   - 布局匹配允许部分匹配（至少3个实体）
   - 实体位置匹配使用容差（0.5单位）
   - 如果找不到海岸，保持原始位置

4. **调试信息**: 输出详细的日志信息，便于排查问题

## 文件结构

```
world-gen/
├── modinfo.lua          # Mod元数据
├── modmain.lua          # Mod入口（导入worldgen_hook）
├── modworldgenmain.lua  # 世界生成阶段入口（已废弃）
├── README.md            # 本文档
├── copy.bat             # 复制脚本
└── scripts/
    ├── constants.lua           # 常量定义
    ├── coast_detection.lua     # 海岸检测
    ├── layout_collection.lua   # 布局收集
    ├── pigking_mover.lua       # 移动逻辑
    └── worldgen_hook.lua       # Hook入口
```

## 猪王布景包含

- **default_pigking**: pigking + 4个insanityrock + 4个sanityrock + 地板tiles
- **torch_pigking**: pigking + 4个pigtorch + 地板tiles

## 注意事项

- 此mod需要在创建新世界时启用才能生效
- 对于已存在的世界，需要重新生成世界才能看到效果
- 如果找不到海边位置，将保持原始位置（会输出警告信息）
- 必须使用Map API进行海岸检测，不使用备用方案


