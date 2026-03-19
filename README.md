# Interface Brownian Dynamics HPC

### MATLAB 项目：模拟异质界面上的单分子跳跃、吸附、停留与扩散

![MATLAB](https://img.shields.io/badge/language-MATLAB-orange)
![MEX](https://img.shields.io/badge/acceleration-MEX%20(C%2FC%2B%2B)-blue)
![Platform](https://img.shields.io/badge/platform-Windows-0078D6)
![Parallel](https://img.shields.io/badge/parallel-parpool%20%7C%20parfeval-success)
![Docs](https://img.shields.io/badge/docs-Chinese-important)

`Interface Brownian Dynamics HPC` 用来做一类具体的问题：分子在异质界面上移动时，会受到缺陷位点、吸附停留时间和外加漂移的共同影响。这个仓库把这类问题拆成了可重复运行的 MATLAB 程序，包括缺陷场生成、单帧动力学推进、参数扫描、并行计算、结果保存和后分析。

主程序默认走 `LinkedCell + block-hash + SharedHash_*.bin + memmapfile + MEX + parfeval` 这条路径。这样做的目的是把大规模参数扫描真正跑起来，同时保留模型里的空间异质性和停留时间统计。

---

## 先看什么

如果你第一次打开这个仓库，建议先看下面几个文件：

- [01_Main/JumpingAtMolecularFreq.m](C:\Users\Administrator\Desktop\GithubHPC\01_Main\JumpingAtMolecularFreq.m)
  主入口。参数、任务展开、并行调度和结果保存都在这里。
- [02_Simulation_Engine/Sub_JumpingBetweenEachFrame_LinkedCell.m](C:\Users\Administrator\Desktop\GithubHPC\02_Simulation_Engine\Sub_JumpingBetweenEachFrame_LinkedCell.m)
  当前主链路的单帧引擎。
- [04_Analysis_Modules/Actual_AdsorptionTime_Filtered.m](C:\Users\Administrator\Desktop\GithubHPC\04_Analysis_Modules\Actual_AdsorptionTime_Filtered.m)
  用于恢复真实吸附时间分布。
- [05_Utils_and_Tests/Verify_Figure6.m](C:\Users\Administrator\Desktop\GithubHPC\05_Utils_and_Tests\Verify_Figure6.m)
  用于检查扩散系数与缺陷间距、平均停留时间之间的标度关系。

---

## 这个项目输出什么

程序运行后会保存：

- 轨迹坐标
- 吸附位置
- 跳跃位移统计
- 跳跃长度分布
- `dx-dy` 概率分布
- MSD 及拟合结果
- `t_ads_history` 真实吸附时间历史
- 运行日志和分析图

结果目录和文件名会带上主要参数，便于回查。

---

## 如何运行

### 环境

当前仓库默认按下面的环境组织：

- Windows
- MATLAB
- Parallel Computing Toolbox
- 可用的 MATLAB Coder / MEX 编译环境

### 主程序

在 MATLAB 中进入仓库根目录后执行：

```matlab
JumpingAtMolecularFreq
```

如果需要改实验参数，请编辑：

- [01_Main/JumpingAtMolecularFreq.m](C:\Users\Administrator\Desktop\GithubHPC\01_Main\JumpingAtMolecularFreq.m)

### 编译 MEX

当前主链路：

```matlab
build_linkedcell_mex
```

旧版静态哈希路径：

```matlab
Do_Compile_HPC
```

仓库里的 `.mexw64` 只适用于 Windows。换到 Linux 或 macOS，需要重新编译。

---

## 项目结构

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

## 每个目录负责什么

### 01_Main

主程序层负责：

- 配置参数
- 生成缺陷场
- 构建索引
- 展开任务表
- 提交并行任务
- 回收结果
- 保存输出

### 02_Simulation_Engine

这一层负责单帧内的微观过程。

- `Sub_JumpingBetweenEachFrame_LinkedCell.m`
  当前主链路入口。
- `Sub_JumpingBetweenEachFrame_LinkedCell_mex.mexw64`
  当前主链路对应的 Windows MEX。
- `Sub_JumpingBetweenEachFrame_mex.m`
  较早期静态哈希版本。
- `Sub_JumpingBetweenEachFrame_mex_mex.mexw64`
  旧版本的 MEX。

### 03_Distributions

这一层定义停留时间怎么采样。

- `Sub_GeneratePowerLawWithMean.m`
  幂律模型。当前版本对不同指数区间做了更稳的处理。
- `Sub_GenerateExponentialWithMean.m`
  指数模型。
- `Sub_GenerateUniformWithMean.m`
  均匀模型。

### 04_Analysis_Modules

这一层负责结果整理和后分析。

- `Sub_TrajectoryAnalysis.m`
  单次任务分析入口。
- `Sub_MergingLocalizationsInSameFrame.m`
  合并同一帧中的定位点。
- `Sub_JumpingAnalysis.m`
  跳跃行为分析。
- `Sub_ShowProbabilityDXDY.m`
  位移分布可视化。
- `Smart_Folder_Plot.m`
  批量汇总结果目录。
- `Actual_AdsorptionTime_Filtered.m`
  从 `t_ads_history` 恢复真实吸附时间分布。
- `CDF.m`
  分布对照绘图。
- `track.m`
  轨迹追踪和可视化。

### 05_Utils_and_Tests

这里放编译脚本和维护脚本。

- `build_linkedcell_mex.m`
  主链路编译脚本。
- `Do_Compile_HPC.m`
  旧路径编译脚本。
- `Verify_Figure6.m`
  标度关系验证脚本。
- `killall.m`
  清理旧并行池和残留 worker。

---

## 模型是什么

这个项目实现的是一个带吸附机制的离散时间随机输运模型。每个微观时间步里，程序处理四件事：

1. 粒子先按扩散和漂移更新位置；
2. 检查它是否进入某个缺陷位点的吸附范围；
3. 如果发生吸附，从指定分布采样停留时间；
4. 如果事件跨过当前观测帧，把剩余时间传给下一帧。

### 自由运动

单步更新写成：

```matlab
dx = k * randn + vx;
dy = k * randn + vy;
xe = xb + dx;
ye = yb + dy;
```

其中：

- `D` 是扩散系数
- `jf` 是跳跃频率
- `tau = 1 / jf` 是单步时间
- `k = sqrt(2 * D * tau) * 1e9` 是热涨落步长
- `vx, vy` 是漂移项

### 吸附判据

程序会在当前位置附近找最近的缺陷位点，并判断：

```matlab
min_d_sq < adR^2
```

若条件成立，就记为发生吸附。

### 停留时间

吸附后可选三类停留时间模型：

- 幂律
- 指数
- 均匀

这部分直接影响轨迹中的停走行为，也会影响宏观上的位移分布和 MSD。

### 跨帧时间

如果吸附或跳跃事件跨过了当前观测帧，程序会保留剩余时间 `t_r`，在下一帧继续使用，而不是在帧边界直接截断。

---

## 当前版本为什么比旧方案快

旧版本的主要问题是：缺陷场表示重、全局搜索多、MATLAB 层高频循环开销大，并行时大数组复制也更明显。

当前版本主要做了几件事：

### 基础区块与旋转模板

不直接存整张全局大图，而是先生成一个基础缺陷区块，再构造四张旋转局部地图。

### block-hash 选图

粒子所在的宏观区块通过哈希规则映射到四张局部模板之一，用较低代价保持空间异质性。

### LinkedCell 索引

每张局部地图都被整理成：

- `AllX`
- `AllY`
- `CellStart`
- `CellCount`

这样每一步只需要检查局部相邻网格，不再全局扫描所有缺陷点。

### 二进制索引与 `memmapfile`

构建好的索引会写入 `SharedHash_Rep*_ds*_adR*.bin` 文件。worker 运行时通过 `memmapfile` 读取数据，再交给 MEX 使用。

### MEX 与异步并行

高频微观循环由 MEX 执行，主程序使用 `parfeval + fetchNext` 组织异步并行任务。

---

## 架构图

![Interface Brownian Dynamics HPC Architecture](assets/architecture-overview.png)

---

## 常用分析脚本

仿真结束后，最常用的是下面几个脚本：

- [04_Analysis_Modules/Sub_TrajectoryAnalysis.m](C:\Users\Administrator\Desktop\GithubHPC\04_Analysis_Modules\Sub_TrajectoryAnalysis.m)
- [04_Analysis_Modules/Smart_Folder_Plot.m](C:\Users\Administrator\Desktop\GithubHPC\04_Analysis_Modules\Smart_Folder_Plot.m)
- [04_Analysis_Modules/Actual_AdsorptionTime_Filtered.m](C:\Users\Administrator\Desktop\GithubHPC\04_Analysis_Modules\Actual_AdsorptionTime_Filtered.m)
- [05_Utils_and_Tests/Verify_Figure6.m](C:\Users\Administrator\Desktop\GithubHPC\05_Utils_and_Tests\Verify_Figure6.m)

前两个偏结果整理，后两个偏物理解释和标度验证。

---

## 最近同步的更新

当前仓库已经同步到最新一批运行与分析脚本，主要包括：

- 更新了 `Sub_JumpingBetweenEachFrame_LinkedCell` 源码与对应 MEX；
- 更新了 `Sub_GeneratePowerLawWithMean.m` 的幂律采样逻辑；
- 合并了最新版 `Actual_AdsorptionTime_Filtered.m`；
- 新增 `Verify_Figure6.m`；
- 清掉了临时外部目录、压缩包和非源码产物。

---

## 说明

- 当前默认针对二维异质界面中的单分子输运问题；
- 当前最成熟的运行路径是 Windows + MATLAB + `.mexw64`；
- 旧版静态哈希路径保留用于对照，不是默认主线；
- 运行时会生成临时 `SharedHash_*.bin` 文件，程序中包含清理逻辑；
- 部分历史 MATLAB 注释有编码遗留，但不影响当前主链路逻辑。

---

## 一句话概括

如果你需要一套能批量跑参数、保留显式缺陷场、输出轨迹统计并继续做吸附时间分析的 MATLAB 项目，这个仓库就是围绕这件事搭起来的。
