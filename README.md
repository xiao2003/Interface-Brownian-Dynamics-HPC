# Interface Brownian Dynamics HPC - 面向界面非高斯输运研究的 MATLAB 高性能仿真框架

![MATLAB](https://img.shields.io/badge/language-MATLAB-orange)
![MEX](https://img.shields.io/badge/acceleration-MEX%20(C%2FC%2B%2B)-blue)
![Platform](https://img.shields.io/badge/platform-Windows-0078D6)
![Parallel](https://img.shields.io/badge/parallel-parpool%20%7C%20parfeval-success)
![Docs](https://img.shields.io/badge/docs-Chinese-important)

Interface Brownian Dynamics HPC 是一个围绕“单分子在异质界面上的吸附、停留、跳跃、漂移与扩散”构建的 MATLAB 数值模拟项目。项目的目标不是简单生成随机轨迹，而是建立一套可用于研究界面非高斯输运、异常停留统计和界面异质性影响的高性能计算框架。当前版本已经形成“参数设定 - 并行仿真 - 轨迹重建 - 统计分析 - 结果归档”的完整闭环，适合毕业论文、答辩展示和后续模型扩展。

---

## 1. 这个项目在解决什么问题

经典布朗扩散模型通常假设粒子处在均匀介质中，步长统计与时间统计都较为规则，因此位移分布和 MSD 演化往往接近高斯扩散理论。但真实界面并不均匀。界面上往往存在：

- 空间上不均匀分布的吸附缺陷位点
- 局域势阱导致的停留时间拉长
- 外加驱动引起的漂移偏置
- 重复吸附、再释放和再跳跃过程

这些机制会使单分子的输运行为偏离经典高斯扩散，出现长尾停留、非对称位移分布、异常 MSD 增长等现象。这个项目的核心问题就是：

1. 不同界面停留时间分布如何改变宏观输运统计量。
2. 表面缺陷的空间异质性如何影响轨迹形态与跳跃行为。
3. 漂移项与随机扩散项耦合后，位移分布与 MSD 会出现什么变化。
4. 如何在大规模参数扫描时，仍然保持仿真可运行、可分析、可追溯。

因此，本项目既是一个科学问题驱动的仿真框架，也是一个工程化优化较强的高性能计算实现。

---

## 2. 当前版本的关键特点

### 2.1 科学建模层面

- 支持幂律、指数、均匀三类停留时间分布。
- 支持界面缺陷位点引发的吸附判据。
- 支持随机扩散与外加漂移同时存在的运动模型。
- 支持多组物理参数的系统扫描，便于研究输运行为随参数变化的规律。

### 2.2 工程实现层面

- 使用 `parpool + parfeval + fetchNext` 实现异步并行调度。
- 使用 `parallel.pool.Constant` 共享缺陷地图，降低 worker 数据复制成本。
- 使用局部 `3x3` 缺陷区域重建，避免全局超大地图常驻内存。
- 使用空间哈希思想在不同区块之间选择旋转缺陷图样。
- 使用 linked-cell 近邻搜索替代全局暴力距离扫描。
- 使用 MEX 版本底层引擎加速逐步推进。
- 使用后台绘图与自动归档机制完成大批量结果导出。

### 2.3 结果输出层面

程序可自动导出：

- 二维 `dx-dy` 热力分布图
- 一维位移直方图
- 跳跃长度分布图
- MSD 拟合曲线
- 参数打包后的 `.mat` 数据文件
- 实验日志与运行耗时记录

---

## 3. 仓库结构

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

### 3.1 各模块职责

- `01_Main`：主程序入口、参数组织、任务下发、结果归档。
- `02_Simulation_Engine`：单帧内跳跃推进、吸附判定、MEX 加速核心。
- `03_Distributions`：停留时间的统计采样函数。
- `04_Analysis_Modules`：轨迹重建、位移统计、MSD 计算和绘图输出。
- `05_Utils_and_Tests`：工具脚本和辅助测试脚本。
- `Archive_Deprecated`：旧版本或废弃脚本的占位目录。

---

## 4. 主程序 `JumpingAtMolecularFreq.m` 的总体设计

主程序是整个项目的调度中枢，核心逻辑可以拆成 6 个阶段。

### 4.1 并行环境初始化

程序启动后先尝试关闭旧并行池，再建立新的本地并行池：

```matlab
NumCores = min(10, feature('numcores'));
pool = parpool('local', NumCores);
```

这里不是机械地使用全部核心，而是显式限制最多 10 核，以避免在桌面环境下造成系统卡顿。这个设计说明项目是面向“可持续批处理”而不是“极限抢占式计算”。

### 4.2 物理参数与扫描参数配置

当前主程序中最重要的参数包括：

```matlab
t_total = 1000;
jf = 10^8;
D = 10^(-10);
adR = 1.0;
L_total = 100 * 1e3;
ds = 40;

Ts_list = [0.02];
tmads_list = [0.05];
TimeIndex_list = [-2.5, 2.5];
Xshiftvelocity_list = [0.0002, 0.0008, 0.002, 0.008] * k;
Yshiftvelocity_list = [0];
DistributionModes = [1, 2, 3];
Repeats = 1:1;
```

这些参数的物理意义如下：

- `jf` 控制单位时间内可能发生多少微观跳跃。
- `D` 决定热噪声驱动下的随机步长尺度。
- `adR` 是分子是否被缺陷位点吸附的几何判据半径。
- `TimeIndex_list` 控制幂律停留时间分布的尾部强弱。
- `Xshiftvelocity_list / Yshiftvelocity_list` 用于描述外加偏置输运。
- `DistributionModes` 用于比较不同停留时间统计模型对输运的影响。

单步热涨落尺度由

```matlab
k = sqrt(2*D*tau) * 1e9;
```

给出，其中 `tau = 1/jf`。这意味着单步随机位移既由扩散系数控制，也受微观跳跃时间步控制。

### 4.3 缺陷地图的预生成与压缩表达

程序并不为整个空间一次性创建超大缺陷图，而是先生成一个基础区块 `L_block = 10000 nm`，再构造其旋转变体：

- `Map1`：基础随机缺陷图
- `Map2`：旋转 90 度
- `Map3`：旋转 180 度
- `Map4`：旋转 270 度

这种设计有两个好处：

1. 用极小的存储成本模拟更大尺度的界面异质性。
2. 保证不同空间区块之间既不是完全相同，也不是完全无规律。

之后，所有地图通过 `parallel.pool.Constant` 共享给并行 worker，避免重复拷贝大对象。

### 4.4 参数任务表展开

程序将所有参数组合展开成任务矩阵 `Tasks`。每一行都对应一组独立仿真条件，包含：

- 采样时间 `Ts`
- 平均吸附时间 `tm_ads`
- 幂律指数 `TI`
- 漂移速度 `vx, vy`
- 分布模式 `DistMode`
- 重复实验编号 `Rep`
- 初始位置 `x0, y0`

这一步的本质是把科学问题离散化为一系列可并行执行的参数样本点。

### 4.5 异步并行提交

任务通过：

```matlab
futures(i) = parfeval(pool, @Worker_JumpingTask, 1, ...)
```

提交给并行池。这意味着每个任务一旦有空闲 worker 就会立即开始，而不是按顺序串行等待。

结果回收则通过：

```matlab
[idx, res] = fetchNext(futures)
```

按完成顺序获取。这样可以避免某个慢任务阻塞整个批次，提高总体吞吐量。

### 4.6 自动归档与分析

任务完成后，主程序会：

1. 清理 NaN 数据。
2. 调用 `Sub_TrajectoryAnalysis` 进行统计分析。
3. 生成带参数编码的子目录与文件名前缀。
4. 保存 `.mat` 数据与图像。
5. 输出实验日志。

当前的目录命名设计，例如：

```text
Rep1_PowerLaw_TI-2.5_Tads0.05_Vx_0.282843
```

使每个结果目录天然可追溯到对应物理参数。

---

## 5. Worker 任务内部的算法逻辑

`Worker_JumpingTask` 是每个并行任务的核心计算单元。相比普通逐帧游走脚本，它最关键的特点是“局部地图 + 动态更新 + 跨帧残余时间”。

### 5.1 不维护全局地图，只维护局部有效区域

worker 内部只在分子附近维护一个局部缺陷集合 `XY_l`。当分子相对当前中心偏移超过阈值 `Th_u` 时，才重建局部地图。这避免了在每个 worker 中长期维护整张大地图，显著降低内存占用。

### 5.2 3x3 邻域区块拼接

局部地图更新时，先根据当前位置求出中心块索引：

```matlab
Ix_center = floor(cx / L_block);
Iy_center = floor(cy / L_block);
```

然后遍历中心块周围的 `3x3` 邻域，将各块内缺陷点映射到全局坐标并拼接。这样做的原因是：分子即使位于块边界附近，也需要看到相邻区块中的缺陷点，不能只依赖单一区块。

### 5.3 用空间哈希决定当前区块用哪张地图

程序使用：

```matlab
MapIdx = mod(Ix * 73856093 + Iy * 19349663, 4) + 1;
```

把二维区块坐标映射到 `1..4` 的编号，从而选择四张旋转地图中的一张。这个做法本质上是轻量级空间哈希，其技术意义在于：

- 同一个区块始终映射为同一张图，保证重复性。
- 相邻区块不会全部共享完全一样的结构。
- 只需保存 4 张基础图样，就能扩展到大范围界面。

从科学建模角度看，这相当于在有限模板上构造一种可重复、可扩展的异质界面背景。

---

## 6. 单帧内跳跃引擎的算法原理

核心推进函数是：

- `Sub_JumpingBetweenEachFrame.m`
- `Sub_JumpingBetweenEachFrame_mex.m`
- `Sub_JumpingBetweenEachFrame_mex_mex.mexw64`

其中 MEX 版本是实际高性能运行时的主力。

### 6.1 运动方程的离散形式

每个微观时间步采用如下形式更新位置：

```matlab
dx = k*randn + vx;
dy = k*randn + vy;
xe = xb + dx;
ye = yb + dy;
```

这可以理解为一个离散化的随机扩散 + 漂移模型：

- `k*randn` 是热噪声导致的随机布朗位移。
- `vx, vy` 是外加场引入的偏置漂移。

因此，粒子的微观运动不是纯随机，也不是纯定向，而是二者叠加。

### 6.2 吸附判据

程序不直接求解复杂界面势场，而采用几何判据：若粒子到最近缺陷点的距离平方满足

```matlab
min_d_sq < adR^2
```

则认为发生一次吸附/停留事件。这个做法等价于把复杂局域界面相互作用压缩为“有效吸附半径”这一物理参数。

### 6.3 停留时间分布采样

发生吸附后，程序依据 `DistMode` 选择不同停留时间模型：

- `DistMode = 1`：幂律分布
- `DistMode = 2`：指数分布
- `DistMode = 3`：均匀分布

这部分是整个模型的科学核心之一。因为界面非高斯输运很多时候不是来源于空间步长异常，而是来源于时间停留统计异常。特别是幂律停留时间分布会引入更强的长尾行为，从而显著影响宏观位移统计和 MSD 演化。

### 6.4 跨帧残余时间 `t_r`

采样窗口结束时，程序不会简单把最后一个微观过程截断，而是把多出来的时间记作 `t_r`，传递到下一帧使用。这意味着相邻帧之间不是完全独立的，而是保留了前一帧末尾未消耗完的停留/跳跃信息。这种处理提高了物理过程在离散采样下的连续性。

---

## 7. Linked-cell 近邻搜索的技术细节

这是当前版本最关键的性能优化之一。

### 7.1 问题来源

如果每一次微观跳跃后，都对局部区域内全部缺陷点做距离扫描，那么复杂度接近 `O(N)`，在缺陷点密度较高、跳跃频率较大时会非常慢。

### 7.2 解决方案

程序先将缺陷点按网格单元组织成 linked-cell 结构：

- `head`：每个网格单元的链表头指针
- `list`：下一个缺陷点索引

这样在粒子移动后，不需要搜索全部缺陷点，只需要检查所在单元及周围 8 个单元。

### 7.3 效果

这种方式把原来近似线性的近邻搜索，变成局部常数级开销。换句话说，程序不再随着缺陷点总数增加而线性恶化，而主要取决于局部邻域的点密度。

这也是本项目能在较高密度缺陷背景下仍然保持可运行性的核心技术基础。

---

## 8. 轨迹分析模块 `Sub_TrajectoryAnalysis.m`

后处理模块不是“附属可视化”，而是整个科学分析链条的一部分。

### 8.1 同帧点合并与轨迹拼接

原始输出先通过 `Sub_MergingLocalizationsInSameFrame` 合并同帧重复点，再使用 `track.m` 拼接为轨迹。`track.m` 使用经典粒子追踪思想，根据最小位移原则构建时间连续轨迹。

### 8.2 核心统计量

分析模块会计算：

- `DX, DY`：相邻步的位移分量
- `DL`：步长模长
- `MSD`：均方位移
- `theta, Dphi`：方向变化
- `SD`：MSD 线性拟合得到的有效扩散斜率指标

这些量对应的科学含义为：

- `DX/DY` 用于观察位移分布是否对称、是否受漂移影响。
- `DL` 用于表征跳跃事件尺度与尾部分布。
- `MSD` 用于判断输运过程更接近正常扩散、受限扩散还是异常扩散。

### 8.3 MSD 的实现方式

程序采用时间平均形式构造 `MSD_TA`，并限制分析窗口：

```matlab
N_MSD = min(10000, size(px_total, 2) - 1);
```

这样做是为了在长轨迹下控制内存开销和计算成本，避免分析阶段成为新的瓶颈。

### 8.4 后台绘图与自动导出

程序在分析开始时关闭默认图窗可见性：

```matlab
set(0, 'DefaultFigureVisible', 'off')
```

其目的不是美观，而是防止并行批处理中大量 figure 弹出造成资源浪费。最终会自动导出：

- `dx-dy` 二维热图
- 一维位移分布图
- 跳跃长度分布图
- MSD 拟合图

并统一保存在对应参数子目录中。

---

## 9. 当前版本的性能优化策略总结

当前版本的优化并不是单点优化，而是分层叠加：

### 9.1 并行层

- `parpool`
- `parfeval`
- `fetchNext`
- `DataQueue`

用于提高批量参数扫描吞吐量。

### 9.2 数据层

- `parallel.pool.Constant`
- 4 张旋转基础缺陷图

用于减少大数组在 worker 间复制。

### 9.3 空间层

- 区块划分
- `3x3` 局部邻域拼接
- 空间哈希选图

用于模拟大尺度异质界面而不显式构造全局巨图。

### 9.4 核心计算层

- linked-cell 近邻搜索
- MEX 加速微观推进

用于降低每一步吸附检测和跳跃推进开销。

### 9.5 后处理层

- 限制 MSD 分析长度
- 后台绘图
- 自动归档

用于降低分析阶段的额外资源消耗。

如果概括成一句话，本项目的实现思路是：

> 用“局部化 + 异步化 + 编译化”的组合策略，把原本代价较高的界面随机输运仿真，变成可批量运行、可自动分析、可直接用于研究展示的工程流程。

---

## 10. 如何运行

推荐在 MATLAB 中进入仓库根目录后执行：

```matlab
addpath(genpath(pwd));
JumpingAtMolecularFreq
```

如果你的 MATLAB 当前目录不在仓库根目录，请确保以下目录已经加入路径：

- `01_Main`
- `02_Simulation_Engine`
- `03_Distributions`
- `04_Analysis_Modules`
- `05_Utils_and_Tests`

### 10.1 建议运行环境

- Windows
- MATLAB
- Parallel Computing Toolbox
- 支持 MEX 的 MATLAB 环境

### 10.2 平台说明

仓库中已包含 `Sub_JumpingBetweenEachFrame_mex_mex.mexw64`，该文件仅适用于 Windows。若迁移到 Linux 或 macOS，需要重新编译 MEX。

---

## 11. 输出结果与文件组织

程序运行后会自动生成：

```text
Simulation_Results/Task_YYYYMMDD_HHMMSS/
Experiment_Logs/SimLog_YYYYMMDD_HHMMSS.txt
```

每个参数组合会拥有独立结果子目录，内部通常包括：

- `.mat` 数据文件
- `dx-dy` 热图
- 位移分布图
- 跳跃长度分布图
- MSD 拟合图

这些运行产物被 `.gitignore` 排除，不会直接进入源码仓库，从而保证仓库更适合版本管理与共享。

---

## 12. 适合论文或答辩时的项目表述

如果需要在毕业论文、中期报告或答辩中概括这个项目，可以直接使用以下表述：

> 本工作构建了一套基于 MATLAB 的界面布朗动力学高性能仿真框架。模型通过停留时间分布、缺陷空间分布和漂移项共同描述单分子在异质界面上的随机输运过程；工程实现上则通过并行调度、空间哈希、局部邻域拼接、linked-cell 搜索和 MEX 加速提高参数扫描效率。程序能够自动输出位移分布、跳跃长度分布和 MSD 等统计量，用于研究界面非高斯输运的形成机制。

---

## 13. 已知局限与后续改进方向

当前版本仍有一些明确限制：

- 主参数仍主要写在脚本内部，缺少统一配置文件。
- 注释存在部分历史编码问题，不影响运行，但影响阅读体验。
- MEX 二进制当前仅提供 Windows 版本。
- 当前统计量主要集中在位移分布和 MSD，后续可以补充非高斯参数、van Hove 函数等更深入分析。
- 当前结果输出偏向批处理归档，后续可以增加更适合答辩展示的汇总脚本或报告脚本。

---

## 14. 仓库地址

GitHub 仓库地址：

[https://github.com/xiao2003/Interface-Brownian-Dynamics-HPC](https://github.com/xiao2003/Interface-Brownian-Dynamics-HPC)
