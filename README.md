# Interface Brownian Dynamics HPC

### 面向界面非高斯输运研究的 MATLAB 高性能仿真框架

![MATLAB](https://img.shields.io/badge/language-MATLAB-orange)
![MEX](https://img.shields.io/badge/acceleration-MEX%20(C%2FC%2B%2B)-blue)
![Platform](https://img.shields.io/badge/platform-Windows-0078D6)
![Parallel](https://img.shields.io/badge/parallel-parpool%20%7C%20parfeval-success)
![Docs](https://img.shields.io/badge/docs-Chinese-important)

Interface Brownian Dynamics HPC 是一个用于研究单分子在异质界面上吸附、停留、跳跃、漂移与扩散行为的 MATLAB 仿真项目。项目聚焦界面非高斯输运这一科学问题，以停留时间统计、缺陷空间异质性和漂移耦合为核心建模对象，通过并行调度、局部地图重建、linked-cell 搜索和 MEX 加速实现大规模参数扫描，并自动输出位移分布、跳跃长度分布和 MSD 等关键统计结果。

---

## Overview

经典布朗扩散模型通常建立在均匀介质、规则时间统计和高斯位移分布的基础上，但真实界面体系往往具有明显异质性。表面缺陷位点、局域吸附势阱、长尾停留时间以及外部驱动场，会共同改变粒子的输运行为，使其偏离经典高斯扩散图像。本项目旨在构建一套既具备物理解释能力、又可支撑高吞吐参数扫描的数值框架，用于研究：

- 停留时间分布如何塑造宏观输运统计量
- 缺陷异质性如何影响轨迹形态和跳跃行为
- 漂移项与随机扩散项耦合后如何改变位移分布与 MSD
- 如何在保持模型可解释性的同时实现高性能批量仿真

---

## Highlights

- 支持幂律、指数、均匀三类停留时间分布建模
- 支持随机扩散与漂移叠加的界面输运模拟
- 使用 `parfeval + fetchNext` 实现异步并行任务调度
- 使用 `parallel.pool.Constant` 共享缺陷地图，降低 worker 拷贝开销
- 使用 4 张旋转基础缺陷图样扩展大尺度异质界面
- 使用 `3x3` 局部区块重建避免全局超大地图常驻内存
- 使用 linked-cell 近邻搜索替代全局暴力距离扫描
- 使用 MEX 引擎加速单帧内微观跳跃推进
- 自动输出 `.mat` 数据包、位移分布图、跳跃长度图和 MSD 拟合图

---

## Repository Layout

```text
.
├── 01_Main/
│   └── JumpingAtMolecularFreq.m
├── 02_Simulation_Engine/
│   ├── Sub_JumpingBetweenEachFrame.m
│   ├── Sub_JumpingBetweenEachFrame_mex.m
│   └── Sub_JumpingBetweenEachFrame_mex_mex.mexw64
├── 03_Distributions/
│   ├── Sub_GenerateExponentialWithMean.m
│   ├── Sub_GeneratePowerLawWithMean.m
│   └── Sub_GenerateUniformWithMean.m
├── 04_Analysis_Modules/
│   ├── Sub_JumpingAnalysis.m
│   ├── Sub_MergingLocalizationsInSameFrame.m
│   ├── Sub_ShowProbabilityDXDY.m
│   ├── Sub_TrajectoryAnalysis.m
│   └── track.m
├── 05_Utils_and_Tests/
│   └── killall.m
├── Archive_Deprecated/
│   └── .gitkeep
├── .gitignore
└── README.md
```

---

## Method

### 1. Physical Model

粒子在界面上执行离散随机运动，其单步推进可写为：

```matlab
dx = k*randn + vx;
dy = k*randn + vy;
```

其中 `k` 由扩散系数 `D` 与跳跃频率 `jf` 决定，`vx, vy` 表示外加漂移项。该模型用热涨落描述随机扩散，用偏置速度描述外场驱动，从而形成界面上的扩散 - 漂移耦合动力学。

若粒子在某一步后进入缺陷吸附半径 `adR` 内，则触发一次吸附事件，并依据给定分布采样停留时间：

- Power-law
- Exponential
- Uniform

这使模型能够直接考察“时间停留统计异常”对非高斯输运的影响。

### 2. Heterogeneous Interface Construction

项目并不显式构造整张全局超大界面图，而是先生成一个基础缺陷区块，再构造 4 张旋转变体。worker 在运行时只重建分子周围的 `3x3` 局部区块，并通过空间哈希把不同区块映射到四张基础图之一。这样既保留了界面异质性，又显著控制了内存成本。

### 3. High-performance Execution

性能优化来自多层组合，而非单点技巧：

- 并行层：`parpool`, `parfeval`, `fetchNext`, `DataQueue`
- 数据层：`parallel.pool.Constant` 共享基础地图
- 空间层：局部区块重建与 `3x3` 邻域拼接
- 搜索层：linked-cell 近邻搜索
- 核心层：MEX 加速微观推进
- 分析层：后台绘图、自动归档、限制 MSD 分析窗口

这使程序能够从“单轨迹演示脚本”升级为“可批量扫描的高性能研究工具”。

### 4. Trajectory Analysis

仿真结束后，原始定位点会经过：

1. 同帧点合并
2. 轨迹拼接
3. 位移统计
4. 跳跃长度统计
5. MSD 构建与线性拟合
6. 图像与 `.mat` 数据导出

输出结果主要包括：

- `dx-dy` 二维热力分布
- 一维位移直方图
- 跳跃长度分布
- MSD 拟合曲线

这些结果共同构成了分析界面非高斯输运行为的核心统计表征。

---

## Main Pipeline

`01_Main/JumpingAtMolecularFreq.m` 负责整个批处理流程：

1. 初始化并行环境
2. 设置物理参数与扫描参数
3. 预生成基础缺陷地图
4. 展开参数任务表
5. 异步提交并回收并行任务
6. 自动完成轨迹分析、结果保存和实验日志输出

该主程序的定位不是单次模拟脚本，而是整个项目的调度入口与实验批处理控制器。

---

## Technical Notes

### Local Map Strategy

程序只维护粒子附近的局部缺陷集合，而不是整张全局地图。这样可以显著降低 worker 的内存占用，并使大尺度界面仿真变得可行。

### Spatial Hashing

区块坐标通过轻量级哈希映射到 4 张旋转地图之一，保证相同区块可重复、相邻区块不完全相同，从而构造大尺度可扩展的异质界面背景。

### Linked-cell Search

缺陷点先按网格单元组织为链表结构。粒子每一步只检查所在单元及周围 8 个单元，避免对全部缺陷点做暴力距离搜索。这是当前版本最重要的性能优化点之一。

### Residual-time Carryover

采样窗口结束后，多出的停留或跳跃时间会通过 `t_r` 传递到下一帧，从而避免人为截断微观过程，提高离散采样下的物理连续性。

---

## Run

在 MATLAB 中进入仓库根目录后执行：

```matlab
addpath(genpath(pwd));
JumpingAtMolecularFreq
```

推荐环境：

- Windows
- MATLAB
- Parallel Computing Toolbox
- 支持 MEX 的 MATLAB 环境

说明：仓库当前包含 `*.mexw64` 二进制，仅适用于 Windows；若迁移到 Linux 或 macOS，需要重新编译 MEX。

---

## Output

程序运行后会自动生成：

```text
Simulation_Results/Task_YYYYMMDD_HHMMSS/
Experiment_Logs/SimLog_YYYYMMDD_HHMMSS.txt
```

其中每个参数组合拥有独立结果子目录，包含图像、统计数据和 `.mat` 数据包。运行产物默认不纳入源码仓库，以保证仓库更适合版本管理与共享。

---

## Project Summary for Thesis or Defense

> 本工作构建了一套基于 MATLAB 的界面布朗动力学高性能仿真框架。模型通过停留时间分布、缺陷空间分布和漂移项共同描述单分子在异质界面上的随机输运过程；工程实现上则通过并行调度、空间哈希、局部邻域拼接、linked-cell 搜索和 MEX 加速提高参数扫描效率。程序能够自动输出位移分布、跳跃长度分布和 MSD 等统计量，用于研究界面非高斯输运的形成机制。

---

## Limitations

- 主参数目前仍主要写在脚本内部，缺少统一配置文件
- 部分注释存在历史编码问题，不影响运行但影响阅读体验
- 当前 MEX 二进制仅提供 Windows 版本
- 当前统计量以位移分布和 MSD 为主，后续可补充更深入的非高斯统计量
- 当前输出更偏向批处理归档，后续可增加答辩展示导向的汇总脚本

---

## Repository

GitHub: [xiao2003/Interface-Brownian-Dynamics-HPC](https://github.com/xiao2003/Interface-Brownian-Dynamics-HPC)
