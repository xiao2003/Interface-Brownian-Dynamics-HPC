# 界面非高斯过程的布朗动力学仿真引擎

本项目是针对固液界面离子/质子反常扩散输运开发的高性能计算仿真平台。

## 核心特性
* **多模式动力学**：支持幂律 (Power-law)、指数 (Exponential) 与均匀分布等界面吸附时间调制模型。
* **HPC 自适应架构**：
  * 基于确定性哈希种子的动态域扩展（Dynamic Domain Expansion）：20 μm Chunk 按需生成并缓存，回访同一区块地形保持一致。
  * Cell-List 近邻索引：仅检索粒子所在网格与 8 邻域，显著降低碰撞检测成本。
  * 势场感知自适应积分：远场大步长快进、近场高频细步长，提高空旷区域整体吞吐。
  * 批次化异步落盘：通过 `DataQueue + afterEach` 存储回调实时写入 `Results_Batch_xxx/TempTasks`，降低长时并行内存峰值。
  * 可追溯随机化：引入批次级 `RunSalt`、任务级 `MotionSeed`、地图级 `MapSeedID`，并输出 `TaskManifest.csv`/`Batch_Metadata.mat`（地图哈希不绑定 Repeat，支持同图多重复统计）。
  * 同参数多种子合并：支持在同一物理参数组下并行多个地图种子（SeedEnsemble），最终做统一系综分析。
  * 空间偏移堆叠分析：多 repeat 以 `1e9 nm` 逻辑偏移后统一送入轨迹分析，避免跨重复误连。

## 目录结构
* `01_Main/`: 全景参数扫描与自适应并行主控程序。
* `02_Simulation_Engine/`: 底层动力学跳跃与碰撞检测引擎 (包含 MEX 优化)。
* `03_Distributions/`: 统计学停留时间分布发生器。
* `04_Analysis_Modules/`: 空间隔离系综平均与 MSD 标度律分析工具。
* `05_Utils_and_Tests/`: 辅助工具与实现审计文档。

## 作者
Wang Beiyan (信息力学与感知工程学院, Xidian University)
