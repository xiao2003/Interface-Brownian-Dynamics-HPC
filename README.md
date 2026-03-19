# Interface Brownian Dynamics HPC

### 用于异质界面单分子跳跃、吸附、停留与扩散模拟的 MATLAB 高性能框架

![MATLAB](https://img.shields.io/badge/language-MATLAB-orange)
![MEX](https://img.shields.io/badge/acceleration-MEX%20(C%2FC%2B%2B)-blue)
![Platform](https://img.shields.io/badge/platform-Windows-0078D6)
![Parallel](https://img.shields.io/badge/parallel-parpool%20%7C%20parfeval-success)
![Docs](https://img.shields.io/badge/docs-Chinese-important)

`Interface Brownian Dynamics HPC` 是一个面向异质界面单分子输运问题的仿真与分析项目。  
它用于研究分子在具有显式缺陷位点的界面上，如何经历自由扩散、漂移、局域吸附、停留和解吸释放，并最终在轨迹、位移分布、跳跃统计和 MSD 等观测量中表现出不同的输运特征。

这个仓库不是单一的仿真脚本，而是一套完整的研究工作流。它将参数扫描、缺陷场生成、MEX 加速、并行调度、结果归档和后分析组织成一条可重复执行的计算链路，适合：

- 研究显式缺陷场中的单分子间歇输运；
- 比较不同停留时间分布对宏观统计量的影响；
- 在多组参数下批量运行界面输运仿真；
- 从原始轨迹中恢复真实吸附时间分布并进行后分析。

当前主链路采用 `LinkedCell + block-hash + SharedHash_*.bin + memmapfile + MEX + parfeval` 架构，用于在保持物理模型清晰的同时，提高大规模参数扫描的执行效率。

---

## 项目架构图

![Interface Brownian Dynamics HPC Architecture](assets/architecture-overview.png)

---

## 这个项目可以做什么

使用当前版本的框架，可以完成以下工作：

1. 定义扩散、吸附、漂移和观测相关参数；
2. 生成基础缺陷区块并构造四张旋转局部地图；
3. 将局部地图转换为 `LinkedCell` 索引并写入 `SharedHash_*.bin`；
4. 通过 `parfeval` 提交异步并行任务；
5. 由每个 worker 使用 `memmapfile` 读取索引数据并调用 MEX 引擎；
6. 输出轨迹、吸附事件、残余时间和 `t_ads_history`；
7. 自动执行轨迹分析、绘图、保存 `.mat` 文件和实验日志；
8. 使用后处理脚本汇总真实吸附时间分布、MSD 和标度关系。

换句话说，这个项目既能用于“跑仿真”，也能直接用于“整理结果”和“生成论文图”。

---

## 快速开始

### 运行环境

当前仓库默认面向以下环境：

- Windows
- MATLAB
- Parallel Computing Toolbox
- 可用的 MATLAB Coder / MEX 编译环境

### 运行主程序

在 MATLAB 中进入仓库根目录后执行：

```matlab
JumpingAtMolecularFreq
```

如果需要修改实验设计，请编辑：

- `01_Main/JumpingAtMolecularFreq.m`

中的参数配置部分。

### 重新编译当前主链路 MEX

```matlab
build_linkedcell_mex
```

如果需要编译旧版静态哈希路径：

```matlab
Do_Compile_HPC
```

说明：

- 仓库中提交的 `.mexw64` 文件仅适用于 Windows；
- Linux 或 macOS 需要重新编译；
- 若 MATLAB 版本或编译器工具链变化，编译脚本可能需要同步调整。

---

## 当前主链路

当前推荐使用的执行路径如下：

1. [JumpingAtMolecularFreq.m](C:\Users\Administrator\Desktop\GithubHPC\01_Main\JumpingAtMolecularFreq.m)
   负责参数配置、缺陷场预生成、任务展开、并行调度、结果回收和归档。
2. [Sub_JumpingBetweenEachFrame_LinkedCell.m](C:\Users\Administrator\Desktop\GithubHPC\02_Simulation_Engine\Sub_JumpingBetweenEachFrame_LinkedCell.m)
   负责单帧内的微观跳跃、局域缺陷搜索、吸附判定和停留时间采样。
3. [Sub_JumpingBetweenEachFrame_LinkedCell_mex.mexw64](C:\Users\Administrator\Desktop\GithubHPC\02_Simulation_Engine\Sub_JumpingBetweenEachFrame_LinkedCell_mex.mexw64)
   是 Windows 下实际执行的 MEX 二进制。
4. [Actual_AdsorptionTime_Filtered.m](C:\Users\Administrator\Desktop\GithubHPC\04_Analysis_Modules\Actual_AdsorptionTime_Filtered.m)
   用于恢复真实吸附时间分布并生成综合分析图。
5. [Verify_Figure6.m](C:\Users\Administrator\Desktop\GithubHPC\05_Utils_and_Tests\Verify_Figure6.m)
   用于验证扩散系数与缺陷间距、平均停留时间之间的标度关系。

仓库中仍保留旧版静态哈希路径，目的是用于对照、回溯和兼容，而不是当前默认入口。

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

- 配置物理参数和扫描参数；
- 生成缺陷区块和旋转地图；
- 构建 `LinkedCell` 索引；
- 写出 `SharedHash_*.bin` 二进制文件；
- 展开任务表；
- 启动并行池并异步提交任务；
- 回收结果并保存输出。

### 02_Simulation_Engine

仿真引擎层负责单帧内的微观动力学推进。

- `Sub_JumpingBetweenEachFrame_LinkedCell.m`
  当前主链路的 MATLAB/Coder 入口。
- `Sub_JumpingBetweenEachFrame_LinkedCell_mex.mexw64`
  当前主链路对应的 MEX。
- `Sub_JumpingBetweenEachFrame_mex.m`
  较早期静态哈希实现。
- `Sub_JumpingBetweenEachFrame_mex_mex.mexw64`
  旧路径对应的 MEX。

### 03_Distributions

停留时间分布采样层。

- `Sub_GeneratePowerLawWithMean.m`
  幂律停留时间模型，当前版本增强了不同参数区间下的稳定采样。
- `Sub_GenerateExponentialWithMean.m`
  指数分布停留模型。
- `Sub_GenerateUniformWithMean.m`
  均匀分布停留模型。

### 04_Analysis_Modules

后处理层负责从轨迹结果中提取物理可解释的统计量。

- `Sub_TrajectoryAnalysis.m`
  单次任务结果的主分析入口。
- `Sub_MergingLocalizationsInSameFrame.m`
  合并同一观测帧内的定位点。
- `Sub_JumpingAnalysis.m`
  跳跃行为与位移统计分析。
- `Sub_ShowProbabilityDXDY.m`
  位移分布可视化。
- `Smart_Folder_Plot.m`
  面向批量结果目录的汇总与绘图脚本。
- `Actual_AdsorptionTime_Filtered.m`
  从 `t_ads_history` 恢复真实微观吸附时间分布，并与宏观统计量联动分析。
- `CDF.m`
  用于分布对照绘图。
- `track.m`
  用于轨迹追踪和可视化。

### 05_Utils_and_Tests

编译与维护层。

- `build_linkedcell_mex.m`
  当前主链路 MEX 编译脚本。
- `Do_Compile_HPC.m`
  旧版静态哈希路径编译脚本。
- `Verify_Figure6.m`
  用于标度关系验证。
- `killall.m`
  用于清理旧并行池和残留 worker。

---

## 模型如何工作

这个项目模拟的是一个带显式吸附机制的离散时间随机输运过程。每个微观时间步都围绕下面四个问题展开：

1. 粒子如何自由移动？
2. 它是否进入了某个缺陷位点的吸附范围？
3. 如果发生吸附，停留多久？
4. 如果事件跨越观测帧，剩余时间如何传递到下一帧？

### 自由扩散与漂移

在自由状态下，粒子的位置更新为：

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
- `k = sqrt(2 * D * tau) * 1e9` 为离散热涨落步长；
- `vx, vy` 为漂移项。

### 吸附判据

程序在当前位置附近搜索候选缺陷位点，并判断：

```matlab
min_d_sq < adR^2
```

若条件满足，则认为粒子进入缺陷位点的有效作用半径并发生吸附。

### 停留时间模型

一旦发生吸附，程序会从以下模型中采样停留时间：

- 幂律分布；
- 指数分布；
- 均匀分布。

这部分决定了吸附事件的时间统计结构，也直接影响宏观输运是否表现出非高斯位移、停走交替或异常扩散。

### 跨帧残余时间

若吸附或跳跃事件跨越当前观测窗口，程序不会简单截断，而是记录剩余时间 `t_r` 并传递给下一帧，以保持时间演化的连续性。

---

## 当前加速思路

当前版本的性能改进主要来自“空间表示重构 + 数据路径重构 + 计算下沉”三部分。

### 1. 基础区块与旋转模板

主程序不会直接生成整张全局超大缺陷图，而是先生成一个基础区块，再构造四张旋转局部地图。这样可以在较低存储成本下保留空间异质性。

### 2. block-hash 空间选图

粒子所在的宏观区块通过哈希规则映射到四张局部模板图之一，从而形成可重复的异质空间分布。

### 3. LinkedCell 局域索引

每张局部地图都会按网格组织成：

- `AllX`
- `AllY`
- `CellStart`
- `CellCount`

这样每个微观步只需要检查局域相邻网格，而不必对整张地图做全局搜索。

### 4. 二进制索引与 `memmapfile`

构建好的索引数组会写入 `SharedHash_Rep*_ds*_adR*.bin` 文件。worker 运行时通过 `memmapfile` 只读映射这些数据，再交给 MEX 使用。

### 5. MEX 与异步并行

高频微观循环由 MEX 完成，主程序使用 `parfeval + fetchNext` 异步调度任务。这一组合使参数扫描更适合大规模并行执行。

---

## 运行流程

当前主程序的执行路径可以概括为：

1. 初始化并行环境；
2. 配置扫描参数；
3. 预生成缺陷地图与 `LinkedCell` 索引；
4. 写出 `SharedHash_*.bin`；
5. 展开任务表；
6. 使用 `parfeval` 异步提交任务；
7. worker 通过 `memmapfile` 读取索引并调用 MEX；
8. 主线程回收结果并保存数据；
9. 后处理脚本提取轨迹统计、真实吸附时间和标度关系。

---

## 输出内容

项目输出不仅包括原始轨迹，还包括可直接用于分析和绘图的数据：

- 粒子轨迹坐标；
- 吸附位置记录；
- 跳跃位移统计；
- 跳跃长度分布；
- `dx-dy` 概率分布；
- MSD 及其拟合量；
- 同帧合并后的定位结果；
- 运行日志；
- `t_ads_history` 真实吸附时间历史。

输出目录和文件名通常编码：

- `Rep`
- 分布类型
- 幂律指数 `TI`
- 平均吸附时间 `Tads`
- 缺陷间距 `DS`
- 吸附半径 `adR`
- 跳跃频率 `jf`
- 漂移与热步长比值

这使结果在后续比较和复现实验时更容易追踪。

---

## 分析脚本

如果你已经完成一批仿真，通常会直接用到以下脚本：

- [Sub_TrajectoryAnalysis.m](C:\Users\Administrator\Desktop\GithubHPC\04_Analysis_Modules\Sub_TrajectoryAnalysis.m)
  单次任务分析入口。
- [Smart_Folder_Plot.m](C:\Users\Administrator\Desktop\GithubHPC\04_Analysis_Modules\Smart_Folder_Plot.m)
  面向一批结果目录的批量汇总。
- [Actual_AdsorptionTime_Filtered.m](C:\Users\Administrator\Desktop\GithubHPC\04_Analysis_Modules\Actual_AdsorptionTime_Filtered.m)
  用于恢复真实吸附时间分布并生成综合图。
- [Verify_Figure6.m](C:\Users\Administrator\Desktop\GithubHPC\05_Utils_and_Tests\Verify_Figure6.m)
  用于检验扩散标度关系。

---

## 最近合并的更新

本次整理后的仓库已经同步到最新一批运行与分析脚本，主要包括：

- 更新了 `Sub_JumpingBetweenEachFrame_LinkedCell` 源码与对应 MEX；
- 更新了 `Sub_GeneratePowerLawWithMean.m` 的幂律采样逻辑；
- 合并了最新版 `Actual_AdsorptionTime_Filtered.m`；
- 新增 `Verify_Figure6.m`；
- 清扫了临时外部目录、压缩包和非源码产物，只保留正式模块目录中的版本。

---

## 适用范围与说明

- 当前仓库默认面向二维异质界面中的单分子输运模拟；
- 当前最成熟的执行路径是 Windows + MATLAB + `.mexw64`；
- 旧版静态哈希路径保留用于对照，不是默认主链路；
- 运行时会生成临时 `SharedHash_*.bin` 文件，程序中包含清理逻辑；
- 部分历史 MATLAB 注释存在编码遗留，但不影响当前主链路逻辑。

---

## 总结

`Interface Brownian Dynamics HPC` 是一套面向异质界面单分子输运研究的仿真与分析框架。  
它将显式缺陷场、停留时间分布、漂移-扩散耦合、`LinkedCell` 索引、二进制映射文件、MEX 加速和异步并行调度组织在同一条工作流中，用于稳定地完成大规模参数扫描，并直接产出轨迹统计、位移分布、MSD 和真实吸附时间等分析结果。

如果你的目标是研究界面上的间歇输运、比较不同等待时间模型，或者需要一套可以批量运行并自动整理结果的单分子仿真框架，这个项目就是为这类工作准备的。
