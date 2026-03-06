# 界面非高斯过程的布朗动力学仿真引擎

本项目是针对固液界面离子/质子反常扩散输运开发的高性能计算仿真平台。

## 核心特性
* **多模式动力学**：支持幂律 (Power-law)、指数 (Exponential) 等多种界面吸附时间调制模型。
* **HPC 自适应架构**：
  * 基于确定性哈希种子的动态域扩展技术（Dynamic Domain Expansion），实现物理视场无限大外延。
  * 引入空间 Cell-List 哈希近邻索引与自适应多尺度时间积分，将碰撞检测复杂度降至 O(1)。
  * 异步 I/O 落盘机制，确保 96 核 EPYC 等高并发环境下的内存长效安全。

## 目录结构
* `01_Main/`: 全景参数扫描与自适应并行主控程序。
* `02_Simulation_Engine/`: 底层动力学跳跃与碰撞检测引擎 (包含 MEX 优化)。
* `03_Distributions/`: 统计学停留时间分布发生器。
* `04_Analysis_Modules/`: 空间隔离系综平均与 MSD 标度律分析工具。

## 作者
Wang Beiyan (Space Science and Technology, Xidian University)
