# Interface Brownian Dynamics HPC

### 用于异质界面单分子输运模拟与统计分析的 MATLAB 框架

![MATLAB](https://img.shields.io/badge/language-MATLAB-orange)
![MEX](https://img.shields.io/badge/acceleration-MEX%20(C%2FC%2B%2B)-blue)
![Platform](https://img.shields.io/badge/platform-Windows-0078D6)
![Parallel](https://img.shields.io/badge/parallel-parpool%20%7C%20parfeval-success)
![Docs](https://img.shields.io/badge/docs-Chinese-important)

`Interface Brownian Dynamics HPC` 用于数值模拟分子在异质界面上的随机输运过程。模型中显式考虑了缺陷位点分布、吸附半径、停留时间分布、漂移项以及离散帧观测机制，并将这些因素组织在同一套 MATLAB 程序中，用于批量参数扫描、并行计算、轨迹分析和结果归档。

当前仓库的默认运行路径采用 `LinkedCell + block-hash + SharedHash_*.bin + memmapfile + MEX + parfeval` 架构。该实现的目标是降低大规模扫描中的局域搜索开销和并行内存压力，同时保留显式缺陷场和停留时间统计对输运行为的影响。

---

## 项目用途

这个项目主要用于以下几类工作：

- 研究显式缺陷场中的单分子跳跃、吸附和解吸过程；
- 比较不同停留时间分布对位移分布、跳跃统计和 MSD 的影响；
- 在多组参数组合下执行批量仿真并统一保存结果；
- 从仿真结果中恢复真实吸附时间分布并进一步做统计分析；
- 检查扩散系数与缺陷间距、平均停留时间等参数之间的标度关系。

程序输出不仅包括轨迹坐标，还包括吸附事件、位移统计、MSD、`t_ads_history` 以及分析图和日志文件，因此既可用于生成原始数据，也可直接用于后续分析。

---

## 项目入口

如果需要理解当前主链路，建议优先阅读以下文件：

- [JumpingAtMolecularFreq.m](C:\Users\Administrator\Desktop\GithubHPC\01_Main\JumpingAtMolecularFreq.m)
  主程序入口，负责参数配置、缺陷场预生成、任务展开、并行调度和结果保存。
- [Sub_JumpingBetweenEachFrame_LinkedCell.m](C:\Users\Administrator\Desktop\GithubHPC\02_Simulation_Engine\Sub_JumpingBetweenEachFrame_LinkedCell.m)
  当前主链路的单帧动力学引擎。
- [Sub_JumpingBetweenEachFrame_LinkedCell_mex.mexw64](C:\Users\Administrator\Desktop\GithubHPC\02_Simulation_Engine\Sub_JumpingBetweenEachFrame_LinkedCell_mex.mexw64)
  Windows 下实际执行的 MEX 二进制。
- [Actual_AdsorptionTime_Filtered.m](C:\Users\Administrator\Desktop\GithubHPC\04_Analysis_Modules\Actual_AdsorptionTime_Filtered.m)
  用于恢复真实吸附时间分布并进行综合分析。
- [Verify_Figure6.m](C:\Users\Administrator\Desktop\GithubHPC\05_Utils_and_Tests\Verify_Figure6.m)
  用于检验扩散系数与缺陷间距、平均停留时间之间的标度关系。

---

## 运行方式

### 运行环境

当前仓库默认按以下环境组织：

- Windows
- MATLAB
- Parallel Computing Toolbox
- 可用的 MATLAB Coder / MEX 编译环境

### 启动主程序

在 MATLAB 中进入仓库根目录后执行：

```matlab
JumpingAtMolecularFreq
```

如需调整实验参数，请修改：

- [JumpingAtMolecularFreq.m](C:\Users\Administrator\Desktop\GithubHPC\01_Main\JumpingAtMolecularFreq.m)

中的参数配置部分。

### 重新编译 MEX

当前主链路对应的编译脚本为：

```matlab
build_linkedcell_mex
```

旧版静态哈希路径对应的编译脚本为：

```matlab
Do_Compile_HPC
```

仓库中提交的 `.mexw64` 文件仅适用于 Windows。若迁移到 Linux 或 macOS，需要重新编译。

---

## 目录结构

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

## 模块说明

### 01_Main

主程序层负责：

- 定义物理参数和扫描参数；
- 生成基础缺陷区块；
- 构造旋转局部地图；
- 构建 `LinkedCell` 索引；
- 写出 `SharedHash_*.bin` 文件；
- 展开任务表并提交并行任务；
- 回收结果并保存输出。

### 02_Simulation_Engine

仿真引擎层负责单帧内的微观动力学推进。

- `Sub_JumpingBetweenEachFrame_LinkedCell.m`
  当前主链路入口。
- `Sub_JumpingBetweenEachFrame_LinkedCell_mex.mexw64`
  当前主链路对应的 MEX。
- `Sub_JumpingBetweenEachFrame_mex.m`
  较早期静态哈希版本。
- `Sub_JumpingBetweenEachFrame_mex_mex.mexw64`
  旧版本的 MEX。

### 03_Distributions

分布层定义吸附停留时间的采样方式。

- `Sub_GeneratePowerLawWithMean.m`
  幂律停留时间模型，当前版本增强了不同指数区间下的稳定采样。
- `Sub_GenerateExponentialWithMean.m`
  指数停留时间模型。
- `Sub_GenerateUniformWithMean.m`
  均匀停留时间模型。

### 04_Analysis_Modules

分析层负责结果整理和后处理。

- `Sub_TrajectoryAnalysis.m`
  单次任务分析入口。
- `Sub_MergingLocalizationsInSameFrame.m`
  合并同一观测帧中的定位点。
- `Sub_JumpingAnalysis.m`
  跳跃行为分析。
- `Sub_ShowProbabilityDXDY.m`
  位移分布可视化。
- `Smart_Folder_Plot.m`
  面向一批结果目录的汇总绘图脚本。
- `Actual_AdsorptionTime_Filtered.m`
  从 `t_ads_history` 恢复真实吸附时间分布。
- `CDF.m`
  用于分布对照绘图。
- `track.m`
  用于轨迹追踪和可视化。

### 05_Utils_and_Tests

编译与维护脚本放在这一层。

- `build_linkedcell_mex.m`
  当前主链路编译脚本。
- `Do_Compile_HPC.m`
  旧路径编译脚本。
- `Verify_Figure6.m`
  标度关系验证脚本。
- `killall.m`
  清理旧并行池和残留 worker。

---

## 模型说明

该项目实现的是一个带吸附机制的离散时间随机输运模型。每个微观时间步内，程序处理以下几个问题：

1. 粒子如何在扩散和漂移作用下更新位置；
2. 粒子是否进入某个缺陷位点的有效吸附范围；
3. 如果发生吸附，停留时间如何采样；
4. 如果事件跨越当前观测帧，剩余时间如何传递到下一帧。

### 自由运动

单步位置更新写为：

```matlab
dx = k * randn + vx;
dy = k * randn + vy;
xe = xb + dx;
ye = yb + dy;
```

其中：

- `D` 为扩散系数；
- `jf` 为跳跃频率；
- `tau = 1 / jf` 为单步时间尺度；
- `k = sqrt(2 * D * tau) * 1e9` 为热涨落步长；
- `vx, vy` 为漂移项。

### 吸附判据

程序在当前位置附近搜索缺陷位点，并判断：

```matlab
min_d_sq < adR^2
```

若条件成立，则认为粒子进入了缺陷位点的有效吸附范围并发生吸附。

### 停留时间

吸附后可选择三类停留时间模型：

- 幂律分布；
- 指数分布；
- 均匀分布。

停留时间分布会直接影响轨迹中的停走行为，也会影响宏观上的位移分布和 MSD。

### 跨帧残余时间

若吸附或跳跃事件跨过当前观测帧，程序会保留剩余时间 `t_r`，并在下一帧继续使用，而不是直接在帧边界截断。

---

## 当前实现的加速思路

当前版本相对于较早期实现，主要在空间表示、局域搜索和并行数据路径上做了调整。

### 基础区块与旋转模板

程序不直接构造整张全局大图，而是先生成一个基础缺陷区块，再构造四张旋转局部地图，用较低存储成本表示更大尺度的异质空间。

### block-hash 选图

粒子所在的宏观区块通过哈希规则映射到四张局部模板之一，从而在较低代价下保留空间异质性。

### LinkedCell 索引

每张局部地图都会整理为：

- `AllX`
- `AllY`
- `CellStart`
- `CellCount`

这样每一步只需检查局部相邻网格，而不需要对全部缺陷点做全局搜索。

### 二进制索引与 `memmapfile`

构建好的索引会写入 `SharedHash_Rep*_ds*_adR*.bin` 文件。worker 运行时通过 `memmapfile` 读取索引数据，再交给 MEX 使用。

### MEX 与异步并行

高频微观循环由 MEX 执行，主程序使用 `parfeval + fetchNext` 组织异步并行任务。

---

## 结果输出

程序运行后通常会保存：

- 轨迹坐标；
- 吸附位置；
- 跳跃位移统计；
- 跳跃长度分布；
- `dx-dy` 概率分布；
- MSD 及拟合结果；
- `t_ads_history` 真实吸附时间历史；
- 分析图和运行日志。

结果目录和文件名中会带有主要参数，便于回查和对照。

---

## 常用分析脚本

仿真结束后，通常会继续使用以下脚本：

- [Sub_TrajectoryAnalysis.m](C:\Users\Administrator\Desktop\GithubHPC\04_Analysis_Modules\Sub_TrajectoryAnalysis.m)
- [Smart_Folder_Plot.m](C:\Users\Administrator\Desktop\GithubHPC\04_Analysis_Modules\Smart_Folder_Plot.m)
- [Actual_AdsorptionTime_Filtered.m](C:\Users\Administrator\Desktop\GithubHPC\04_Analysis_Modules\Actual_AdsorptionTime_Filtered.m)
- [Verify_Figure6.m](C:\Users\Administrator\Desktop\GithubHPC\05_Utils_and_Tests\Verify_Figure6.m)

其中前两者更偏向结果整理，后两者更偏向物理解释和标度验证。

---

## 当前版本已同步的更新

当前仓库已经同步到最新一批运行与分析脚本，主要包括：

- 更新了 `Sub_JumpingBetweenEachFrame_LinkedCell` 源码与对应 MEX；
- 更新了 `Sub_GeneratePowerLawWithMean.m` 的幂律采样逻辑；
- 合并了最新版 `Actual_AdsorptionTime_Filtered.m`；
- 新增 `Verify_Figure6.m`；
- 清理了临时外部目录、压缩包和非源码产物。

---

## 说明

- 当前默认针对二维异质界面中的单分子输运问题；
- 当前最成熟的运行路径为 Windows + MATLAB + `.mexw64`；
- 旧版静态哈希路径保留用于对照，不是默认主线；
- 运行时会生成临时 `SharedHash_*.bin` 文件，程序中包含对应清理逻辑；
- 部分历史 MATLAB 注释存在编码遗留，但不影响当前主链路逻辑。

---

## 架构图

![Interface Brownian Dynamics HPC Architecture](assets/architecture-overview.png)
