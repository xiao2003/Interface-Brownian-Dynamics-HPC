# Interface Brownian Dynamics HPC

### 面向异质界面单分子跳跃-吸附-停留-扩散过程的高性能仿真与统计分析框架

![MATLAB](https://img.shields.io/badge/language-MATLAB-orange)
![MEX](https://img.shields.io/badge/acceleration-MEX%20(C%2FC%2B%2B)-blue)
![Platform](https://img.shields.io/badge/platform-Windows-0078D6)
![Parallel](https://img.shields.io/badge/parallel-parpool%20%7C%20parfeval-success)
![Docs](https://img.shields.io/badge/docs-Chinese-important)

`Interface Brownian Dynamics HPC` 是一个围绕异质界面单分子输运问题构建的 MATLAB 高性能仿真项目。该项目以单分子在界面上的自由扩散、漂移、缺陷捕获、吸附停留、解吸释放以及相机帧采样观测为基本过程，建立了一套兼具物理可解释性、参数可扫描性和工程可扩展性的数值实验框架。

项目的目标并非仅仅生成随机轨迹，而是构建一条完整的计算链路，用于系统研究以下问题：

- 界面缺陷的空间异质性如何改变单分子的宏观输运行为；
- 吸附停留时间的统计分布如何导致非高斯位移、间歇性停滞和异常扩散；
- 外加漂移与热扩散耦合后，位移分布和 MSD 等统计量如何发生偏移或变形；
- 在大规模参数扫描条件下，如何以较高吞吐量稳定完成仿真、归档和后分析。

从工程角度看，本仓库已经形成了清晰的模块化结构，包括：

- 主程序层：负责实验编排、参数扫描、并行调度与结果归档；
- 仿真引擎层：负责单帧内的微观跳跃与吸附动力学推进；
- 分布采样层：负责不同停留时间模型的随机采样；
- 分析后处理层：负责轨迹重构、统计分析、绘图和批量汇总；
- 编译与维护层：负责 MEX 编译和运行环境清理。

当前版本的主链路采用：

- `LinkedCell` 空间索引；
- `block-hash` 空间区块选图；
- `SharedHash_*.bin` 二进制索引文件；
- `memmapfile` 只读映射；
- MEX 微观步进计算；
- `parfeval + fetchNext` 异步并行调度。

这一组合使得项目能够同时满足科学建模需求和高性能计算需求。

---

## 最近更新

本次整理后的仓库主线已经同步到最新一批运行与分析脚本，重点包括：

- 合并了最新版 `Sub_JumpingBetweenEachFrame_LinkedCell` 源码与对应 MEX 二进制；
- 更新了 `Sub_GeneratePowerLawWithMean.m`，增强了不同幂律指数区间下的稳定采样能力；
- 合并了最新版 `Actual_AdsorptionTime_Filtered.m`，扩展了自动数据寻址和综合分析输出；
- 新增 `Verify_Figure6.m`，用于验证扩散系数与缺陷间距、平均停留时间之间的标度关系；
- 清扫了外部临时目录、压缩包与非源码产物，只保留模块化目录中的正式版本。

---

## 项目架构图

![Interface Brownian Dynamics HPC Architecture](assets/architecture-overview.png)

---

## 1. 项目研究对象与目标

本项目关注的对象是异质界面上的单分子随机输运问题。与理想均匀介质中的经典布朗运动不同，界面体系通常同时具有如下特征：

- 缺陷位点空间分布不均匀；
- 分子可能在局部位点发生反复吸附与解吸；
- 吸附停留时间可能服从长尾分布而非简单指数分布；
- 外加场或背景流动会引入漂移项；
- 实验观测往往以离散帧的方式采样，而非连续时间记录。

在上述条件下，体系可能表现出一系列非经典输运现象，例如：

- 位移分布偏离高斯形式；
- 轨迹呈现明显的停走交替特征；
- 跳跃长度和等待时间出现宽分布或长尾分布；
- MSD 与时间的关系偏离简单线性规律；
- 统计结果对吸附半径、缺陷间距和停留时间分布高度敏感。

因此，本项目的核心目标是：

**从微观的缺陷捕获与停留规则出发，建立与宏观轨迹统计量之间的定量联系，并在大规模参数扫描下稳定实现这一计算流程。**

---

## 2. 项目能力概述

当前框架已经能够完成以下完整流程：

1. 在主程序中定义扩散、吸附、漂移和观测相关参数；
2. 生成基础缺陷区块，并构造四张旋转局部地图；
3. 将局部缺陷地图转换为 `LinkedCell` 索引结构；
4. 将索引结果写入 `SharedHash_*.bin` 二进制文件；
5. 通过 `parfeval` 提交异步并行任务；
6. 由每个 worker 通过 `memmapfile` 只读映射缺陷索引；
7. 调用底层 MEX 引擎完成微观跳跃、吸附和停留计算；
8. 回收轨迹、吸附事件和真实吸附时间历史；
9. 自动执行轨迹分析、统计绘图、结果保存与日志记录。

因此，本项目不是单一算法脚本，而是一套用于数值实验、论文制图和性能评估的仿真-分析一体化平台。

---

## 3. 项目目录结构

```text
.
|-- 01_Main/
|   `-- JumpingAtMolecularFreq.m
|-- 02_Simulation_Engine/
|   |-- Sub_JumpingBetweenEachFrame.m
|   |-- Sub_JumpingBetweenEachFrame_LinkedCell.m
|   |-- Sub_JumpingBetweenEachFrame_LinkedCell_mex.mexw64
|   |-- Sub_JumpingBetweenEachFrame_mex.m
|   `-- Sub_JumpingBetweenEachFrame_mex_mex.mexw64
|-- 03_Distributions/
|   |-- Sub_GenerateExponentialWithMean.m
|   |-- Sub_GeneratePowerLawWithMean.m
|   `-- Sub_GenerateUniformWithMean.m
|-- 04_Analysis_Modules/
|   |-- Actual_AdsorptionTime_Filtered.m
|   |-- CDF.m
|   |-- Smart_Folder_Plot.m
|   |-- Sub_JumpingAnalysis.m
|   |-- Sub_MergingLocalizationsInSameFrame.m
|   |-- Sub_ShowProbabilityDXDY.m
|   |-- Sub_TrajectoryAnalysis.m
|   `-- track.m
|-- 05_Utils_and_Tests/
|   |-- build_linkedcell_mex.m
|   |-- Do_Compile_HPC.m
|   |-- Verify_Figure6.m
|   `-- killall.m
|-- Archive_Deprecated/
|   `-- .gitkeep
|-- assets/
|   `-- architecture-overview.png
|-- .gitignore
`-- README.md
```

---

## 4. 各模块职责

### 4.1 主程序层

`01_Main/JumpingAtMolecularFreq.m` 是整个项目的主入口。它承担以下职责：

- 配置物理参数和扫描参数；
- 生成初始缺陷区块；
- 构造四张旋转局部地图；
- 构建 `LinkedCell` 索引；
- 生成 `SharedHash_*.bin` 二进制索引文件；
- 展开参数任务表；
- 启动并行池并分发异步任务；
- 回收计算结果；
- 执行后处理、保存数据并生成实验日志。

从本质上说，该文件将一个科学问题转换为可重复执行的批量计算流程。

### 4.2 仿真引擎层

`02_Simulation_Engine/` 存放单帧内微观动力学推进引擎：

- `Sub_JumpingBetweenEachFrame_LinkedCell.m`
  当前主链路的 MATLAB/Coder 入口，负责基于 `LinkedCell` 索引完成局域缺陷搜索、吸附判定、停留时间采样和残余时间传递。
- `Sub_JumpingBetweenEachFrame_LinkedCell_mex.mexw64`
  当前 Windows 平台下正式使用的 MEX 二进制。
- `Sub_JumpingBetweenEachFrame_mex.m`
  较早期的静态哈希版本，保留用于回溯、对照和兼容。
- `Sub_JumpingBetweenEachFrame_mex_mex.mexw64`
  上述旧路径对应的 MEX 二进制。

该层的核心设计是：由 MATLAB 负责实验组织，由 MEX 负责高频微观循环计算。

### 4.3 分布采样层

`03_Distributions/` 定义吸附停留时间的随机采样方式：

- `Sub_GeneratePowerLawWithMean.m`
  幂律停留时间模型，最新版同时处理有限均值、截断幂律以及短尾参数区间下的稳定采样情况。
- `Sub_GenerateExponentialWithMean.m`
  指数分布停留模型，用于表示无记忆吸附过程。
- `Sub_GenerateUniformWithMean.m`
  均匀分布停留模型，通常作为对照模型使用。

这一层决定了吸附事件的时间统计结构，是异常输运建模中的关键组成部分。

### 4.4 分析后处理层

`04_Analysis_Modules/` 用于从原始输出中提取物理可解释的统计结果：

- `Sub_TrajectoryAnalysis.m`
  单次任务结果的主分析入口。
- `Sub_MergingLocalizationsInSameFrame.m`
  用于合并同一观测帧中的定位点。
- `Sub_JumpingAnalysis.m`
  用于跳跃行为与位移统计分析。
- `Sub_ShowProbabilityDXDY.m`
  用于位移分布可视化。
- `Smart_Folder_Plot.m`
  用于批量目录汇总、结果筛选与绘图。
- `Actual_AdsorptionTime_Filtered.m`
  用于从保存的 `t_ads_history` 中恢复真实微观吸附时间分布，并生成更完整的微观-宏观联合分析图。
- `CDF.m`
  用于累计分布或分布对照绘图。
- `track.m`
  用于轨迹可视化与辅助追踪分析。

### 4.5 编译与维护层

`05_Utils_and_Tests/` 提供运行维护和编译支持：

- `build_linkedcell_mex.m`
  当前主链路 `LinkedCell` MEX 的编译脚本；
- `Do_Compile_HPC.m`
  较早期静态哈希版 MEX 的编译脚本；
- `Verify_Figure6.m`
  用于复现实验标度关系并验证扩散系数与缺陷间距、平均停留时间之间的关系；
- `killall.m`
  用于清理旧并行池、残留 worker 和相关环境状态。

---

## 5. 物理模型说明

本项目实现的是一个带吸附机制的离散时间随机输运模型。其最基本的微观步骤包含“自由运动 -> 吸附判定 -> 停留时间采样 -> 时间推进”四个环节。

### 5.1 自由扩散与漂移

在自由状态下，粒子在单个微观时间步上的位置更新为：

```matlab
dx = k * randn + vx;
dy = k * randn + vy;
xe = xb + dx;
ye = yb + dy;
```

其中：

- `D` 为理论扩散系数；
- `jf` 为分子跳跃频率；
- `tau = 1 / jf` 为单次跳跃的时间尺度；
- `k = sqrt(2 * D * tau) * 1e9` 为离散热涨落步长尺度；
- `vx, vy` 为漂移项。

因此，该模型本质上是一个离散化的扩散-漂移耦合模型。

### 5.2 缺陷吸附判据

在每次尝试更新位置之后，程序会在当前位置周围局域搜索缺陷位点，并计算到最近候选缺陷的距离平方。当满足

```matlab
min_d_sq < adR^2
```

时，视为粒子进入了缺陷位点的有效作用范围并发生吸附。其中 `adR` 表示有效吸附半径。

这种写法的优点在于：

- 既保留了显式几何上的空间异质性；
- 又避免了用平均场势函数替代局域界面作用；
- 使吸附概率由空间结构和随机运动共同决定。

### 5.3 停留时间采样

粒子一旦被吸附，系统即依据所选模型采样一个停留时间：

- 幂律分布：用于表示可能具有长尾行为的停留统计；
- 指数分布：用于表示无记忆的停留过程；
- 均匀分布：用于构造有界对照模型。

这部分在物理上非常关键，因为在许多异常输运问题中，宏观统计偏离经典布朗运动的原因并不一定来自异常步长，而往往主要来自停留时间分布本身。

### 5.4 跨帧残余时间

若一个吸附或跳跃事件跨越了当前观测窗口，程序不会简单截断，而是将剩余时间记录为 `t_r` 并传递给下一帧。这样可以保证：

- 帧与帧之间的时间演化是连续的；
- 观测边界不会引入非物理的重置效应；
- 统计结果能够更接近真实实验采样过程。

---

## 6. 空间建模与加速原理

当前版本最重要的工程升级来自对空间结构表示与近邻搜索方式的重构。项目不再依赖早期“全局显式缺陷图 + MATLAB 层暴力筛选”的方法，而是采用“基础区块 + 旋转模板 + block-hash + linked-cell + MEX”的组合架构。

### 6.1 基础区块与四张旋转地图

主程序首先生成一个边长为 `L_block` 的基础缺陷区块。随后以该区块为基底构造四张局部地图：

- 原始地图；
- 旋转 90 度地图；
- 旋转 180 度地图；
- 旋转 270 度地图。

这种设计有两个目的：

- 在不存储全局超大地图的前提下保留局部空间异质性；
- 用有限数量的模板块覆盖更大尺度的界面区域。

### 6.2 block-hash 宏观区块选图

粒子处于全局空间中的某一宏观区块时，程序根据区块坐标 `bx_global`、`by_global` 以及 `TimeSeed` 计算哈希值，并由此确定当前区块使用哪一张局部模板图。其效果是：

- 同一空间区块始终映射到同一局部模板；
- 宏观尺度上形成可重复的空间异质图样；
- 计算代价远低于显式构建整张全局缺陷图。

这里的 hash 不是加密意义上的散列，而是一种低成本、可重复的空间映射机制。

### 6.3 LinkedCell 局域索引

每张局部地图都会按 `cell_size` 划分为规则网格，并整理成以下结构：

- `AllX`：按网格顺序拼接后的缺陷 `x` 坐标；
- `AllY`：按网格顺序拼接后的缺陷 `y` 坐标；
- `CellStart`：某个网格对应点列在 `AllX / AllY` 中的起始位置；
- `CellCount`：某个网格对应点列包含的点数。

这样，粒子在每个微观步只需要检查自身所在网格及相邻少数网格，而不需要对整张地图或全体缺陷点做全局扫描。其直接收益包括：

- 局域搜索规模显著下降；
- 内层循环更适合 MEX 顺序访问；
- 并行运行时内存路径更简单。

### 6.4 二进制索引与 `memmapfile`

构建好的索引数组会被顺序写入 `SharedHash_Rep*_ds*_adR*.bin` 文件。worker 在执行任务时，通过 `memmapfile` 将这些文件映射为只读数组视图，然后再调用 MEX 引擎。

这一设计的意义在于：

- 将地图预处理与运行时搜索解耦；
- 降低大数组在并行任务中的直接传递压力；
- 使底层引擎可以读取连续存储的坐标表和网格索引。

因此，当前主链路的加速逻辑可以概括为：

**宏观上用 block-hash 实现异质区块选图，局部上用 LinkedCell 实现近邻候选筛选，底层再用 MEX 实现高频微观推进。**

---

## 7. 主程序执行流程

当前主程序 [JumpingAtMolecularFreq.m](01_Main/JumpingAtMolecularFreq.m) 的完整工作流可分为以下阶段。

### 7.1 并行环境初始化

程序启动时会清理旧并行池，结合任务总数和机器核心数重新建立本地并行池，从而在吞吐量和系统保留资源之间取得平衡。

### 7.2 参数配置与扫描空间定义

主程序中定义了扩散、吸附、漂移和观测相关参数，例如：

- `t_total`：总观测时间；
- `D`：理论扩散系数；
- `jf_list`：跳跃频率扫描列表；
- `adR_list`：吸附半径扫描列表；
- `ds_list`：缺陷平均间距扫描列表；
- `tmads_list`：平均吸附时间列表；
- `TimeIndex_list`：幂律指数列表；
- `DistributionModes`：停留时间模型列表；
- `Vx_ratio_list / Vy_ratio_list`：漂移比值列表；
- `Repeats`：重复实验编号。

这些参数共同定义了实验设计空间。

### 7.3 缺陷地图预生成与索引构建

对于每组 `Rep`、`ds` 和 `adR`，主程序会：

1. 生成基础缺陷区块；
2. 构造四张旋转局部地图；
3. 将缺陷点按 `LinkedCell` 规则排序；
4. 构建 `AllX / AllY / CellStart / CellCount`；
5. 写出对应的 `SharedHash_*.bin` 文件。

这一阶段把高成本预处理从运行时微观循环中前移出来。

### 7.4 任务表展开

程序将所有参数组合打包为 `Tasks` 矩阵，每一行代表一组独立仿真条件。这样可以把科学问题明确地离散为一系列可调度任务。

### 7.5 异步并行调度

任务通过 `parfeval` 异步提交，并通过 `fetchNext` 按完成顺序回收。与按顺序阻塞等待相比，这种机制具有以下优势：

- 快任务不会被慢任务拖住；
- 总体吞吐量更高；
- 可以结合 `DataQueue` 实时刷新进度；
- 更适合大规模参数扫描与长时间运行。

### 7.6 worker 侧二进制映射与 MEX 执行

每个 worker 根据任务参数定位相应的 `SharedHash_*.bin` 文件，通过 `memmapfile` 构造数组视图后，调用 `Sub_JumpingBetweenEachFrame_LinkedCell_mex` 执行微观仿真。引擎输出包括：

- 更新后的粒子位置；
- 吸附发生时的坐标；
- 跨帧残余时间；
- 每次真实吸附事件对应的 `t_ads_history`。

### 7.7 自动归档与后处理

任务完成后，主线程会自动：

- 清理无效数据；
- 调用轨迹分析模块；
- 生成参数编码的结果目录；
- 保存 `.mat` 数据；
- 导出统计图像；
- 记录实验日志。

由此形成一套完整的“仿真-分析-归档”流水线。

---

## 8. 输出内容与结果组织

项目输出不仅包含原始轨迹坐标，还包含用于进一步科研分析的多类结果：

- 轨迹坐标与定位序列；
- 吸附位置记录；
- 跳跃位移统计；
- 跳跃长度分布；
- `dx-dy` 概率分布；
- MSD 及相关拟合量；
- 同帧合并后的定位结果；
- 批量绘图结果；
- 运行日志；
- `t_ads_history` 真实吸附时间历史。

结果文件和目录命名中通常编码：

- `Rep`；
- 分布类型；
- 幂律指数 `TI`；
- 平均吸附时间 `Tads`；
- 缺陷间距 `DS`；
- 吸附半径 `adR`；
- 跳跃频率 `jf`；
- 漂移与热步长的比值。

因此，项目输出天然具备良好的参数可追溯性，便于后续论文制图、参数对比和复现实验。

---

## 9. 分析模块说明

项目的分析层不是附加功能，而是主框架的重要组成部分。

### 9.1 轨迹分析

`Sub_TrajectoryAnalysis.m` 负责对单次任务输出执行轨迹层面的核心分析，包括轨迹重建、位移统计和基础图形生成。

### 9.2 同帧定位合并

`Sub_MergingLocalizationsInSameFrame.m` 用于将同一观测帧内的定位点进行合并，以降低重复采样对轨迹统计的干扰。

### 9.3 跳跃统计与概率图

`Sub_JumpingAnalysis.m` 和 `Sub_ShowProbabilityDXDY.m` 用于提取跳跃长度、位移分量分布及其可视化结果，是研究非高斯输运的重要工具。

### 9.4 批量结果汇总

`Smart_Folder_Plot.m` 用于针对一批结果目录执行统一筛选、批量绘图和趋势比较，适合参数扫描结束后的汇总分析。

### 9.5 真实吸附时间恢复

`Actual_AdsorptionTime_Filtered.m` 是当前版本一个很重要的分析扩展。它不再只依赖理论设定的停留时间分布，而是直接从保存的 `t_ads_history` 中恢复真实实现的微观吸附时间分布，并将其与宏观轨迹和 MSD 结果对应起来。最新版脚本进一步补充了自动数据寻址、综合全景图输出以及与轨迹时域行为联动的分析流程。

这使项目能够同时比较：

- 理论输入的停留时间模型；
- 仿真过程中实际实现的吸附时间统计；
- 宏观输运量随吸附统计变化的响应。

这对于解释结果和撰写论文都非常关键。

### 9.6 标度关系验证工具

`Verify_Figure6.m` 用于针对最新结果目录自动提取扩散系数，并检验其与缺陷平均间距及平均吸附时间之间的标度关系。该脚本适合用于方法学验证、补充材料制图以及对特定理论关系的快速复现。

---

## 10. 当前版本相对于旧方案的改进

当前版本相对于更早期的“全局缺陷图 + MATLAB 层暴力搜索”方案，提升并不只是代码整理，而是运行架构的系统性重构。核心改进包括：

- 用基础区块和旋转模板替代全局显式大图；
- 用 `block-hash` 生成可重复的宏观空间异质性；
- 用 `LinkedCell` 将近邻搜索限制在局域候选网格中；
- 用二进制索引文件和 `memmapfile` 改善并行任务的数据组织方式；
- 用 MEX 承担高频微观循环；
- 用 `parfeval + fetchNext` 实现异步高吞吐并行执行；
- 显式保存 `t_ads_history`，扩展了后分析深度。

因此，项目当前的价值在于：它把空间异质性、时间异质性、底层性能优化和后分析解释能力整合在同一套稳定框架中。

---

## 11. 运行方法

### 11.1 运行环境

当前仓库默认面向以下环境：

- Windows；
- MATLAB；
- Parallel Computing Toolbox；
- 可用的 MATLAB Coder / MEX 编译环境。

### 11.2 启动仿真

在 MATLAB 中进入仓库根目录后，执行：

```matlab
JumpingAtMolecularFreq
```

若需要调整实验设计，请直接编辑：

- `01_Main/JumpingAtMolecularFreq.m`

中的参数配置部分。

### 11.3 重新编译 MEX

若需重新编译当前主链路使用的 `LinkedCell` MEX，可在 MATLAB 中执行：

```matlab
build_linkedcell_mex
```

若需要编译旧版静态哈希路径，可执行：

```matlab
Do_Compile_HPC
```

说明：

- 仓库中提交的 `.mexw64` 文件仅适用于 Windows；
- Linux 或 macOS 需重新编译；
- 若 MATLAB 版本、编译器工具链或 Coder 行为发生变化，编译脚本也可能需要相应调整。

---

## 12. 项目特点与创新点

从工程实现上看，本项目的主要特点包括：

- 使用 MATLAB 进行实验编排和结果分析；
- 使用 MEX 承担高频微观动力学计算；
- 使用 `LinkedCell` 替代暴力近邻搜索；
- 使用 `block-hash` 在低存储成本下实现宏观异质空间映射；
- 使用二进制索引与 `memmapfile` 组织 worker 侧地图数据；
- 使用异步并行调度提高参数扫描吞吐；
- 使用 `t_ads_history` 将微观停留统计直接纳入后分析。

从科学计算角度看，本项目的创新价值在于：它不是分别处理扩散、吸附、统计或绘图，而是把以下因素统一到一条计算链路中：

- 空间异质性；
- 停留时间异质性；
- 漂移与扩散耦合；
- 有限帧观测机制；
- 批量实验归档与结果复现。

这使得项目既适合作为论文中的核心数值实验平台，也适合作为后续扩展更复杂界面模型的基础代码框架。

---

## 13. 注意事项

- 仓库中保留了部分旧版引擎与编译脚本，目的是支持对照、回溯和兼容，而非作为当前默认主链路；
- 运行时会产生临时 `SharedHash_*.bin` 文件，程序中包含对应的清理逻辑；
- 由于当前主链路依赖 Windows MEX 二进制，跨平台使用时必须重新编译；
- 部分历史 MATLAB 文件注释存在编码遗留问题，但不影响当前主链路的运行逻辑。

---

## 14. 总结

`Interface Brownian Dynamics HPC` 是一套面向异质界面单分子输运问题的仿真与分析一体化平台。其当前主架构以基础区块缺陷图、旋转模板、`block-hash` 空间映射、`LinkedCell` 局域索引、二进制映射文件、MEX 微观步进和异步并行调度为核心，能够在保持物理可解释性的前提下高效完成大规模参数扫描，并自动生成轨迹统计、位移分布、MSD 和真实吸附时间等分析结果。

简而言之，该项目同时具备以下三类价值：

- 物理建模价值：能够明确表达吸附、停留、漂移和扩散对输运统计的作用；
- 工程实现价值：能够以较高效率支撑批量计算与结果归档；
- 科研应用价值：能够直接服务于论文分析、参数比较、机制解释和结果展示。
