# Interface Brownian Dynamics HPC

本项目是一个面向界面布朗动力学研究的 MATLAB 高性能仿真代码库，主要用于模拟单分子在异质界面上的吸附、停留、跳跃、漂移与扩散行为，并对仿真轨迹进行自动化统计分析。README 采用中文撰写，便于论文答辩、项目汇报和后续代码维护时直接引用。

## 1. 项目简介

本仓库围绕“界面非高斯输运过程”的数值模拟展开，核心工作流包括：

- 基于布朗动力学思想的单分子随机运动模拟
- 表面吸附停留时间的多分布采样
- 不同漂移速度与参数组合的批量扫描
- 基于 MATLAB 并行工具箱的多核并行计算
- 对原始轨迹进行拼接、追踪和动力学统计分析
- 自动导出 `.mat` 数据包、位移分布图、跳跃长度分布图和 MSD 拟合图

当前版本适用于 Windows + MATLAB 环境，适合本地工作站或小型 HPC 风格批量计算任务。

## 2. 代码特色

### 2.1 高性能并行计算

主程序使用 `parpool`、`parfeval`、`fetchNext`、`parallel.pool.Constant` 等机制，将参数扫描任务拆分后并行投递到多个 CPU 核心执行，以提升批量仿真的整体吞吐量。

### 2.2 多种停留时间分布模型

本项目当前支持 3 类吸附停留时间分布：

- 幂律分布
- 指数分布
- 均匀分布

对应函数位于 `03_Distributions/` 目录下。

### 2.3 自动化结果分析

仿真结束后，程序会调用轨迹分析模块，自动计算并导出：

- 二维 `dx-dy` 热力分布图
- 一维位移直方图
- 跳跃长度分布图
- MSD 曲线与线性拟合结果
- 部分轨迹统计量与中间矩阵数据

### 2.4 MEX 加速

项目包含已经编译好的 Windows 平台 MEX 二进制文件，可用于加速逐帧跳跃计算，降低 MATLAB 纯脚本执行时的时间开销。

## 3. 当前仓库目录结构

整理后的仓库按照远端既有风格组织为以下结构：

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

## 4. 各目录功能说明

### 4.1 `01_Main`

该目录存放项目主入口脚本：

- `JumpingAtMolecularFreq.m`

此文件负责：

- 初始化并行池
- 设置物理参数和扫描参数
- 构造任务队列
- 分发并收集并行任务
- 调用后处理分析模块
- 导出日志与结果文件

答辩时可以将其概括为“整个仿真流程的调度中枢”。

### 4.2 `02_Simulation_Engine`

该目录保存仿真核心引擎相关代码：

- `Sub_JumpingBetweenEachFrame.m`：逐帧跳跃的 MATLAB 实现
- `Sub_JumpingBetweenEachFrame_mex.m`：MEX 接口封装
- `Sub_JumpingBetweenEachFrame_mex_mex.mexw64`：Windows 下已编译的 MEX 二进制

这部分对应答辩中的“核心数值推进模块”。

### 4.3 `03_Distributions`

该目录用于生成不同类型的吸附停留时间：

- `Sub_GeneratePowerLawWithMean.m`
- `Sub_GenerateExponentialWithMean.m`
- `Sub_GenerateUniformWithMean.m`

可在答辩中将其描述为“停留时间统计模型层”。

### 4.4 `04_Analysis_Modules`

该目录存放轨迹重建与统计分析模块：

- `Sub_MergingLocalizationsInSameFrame.m`：同帧定位点合并
- `track.m`：轨迹拼接/追踪
- `Sub_JumpingAnalysis.m`：跳跃次数与停留时间分析
- `Sub_ShowProbabilityDXDY.m`：位移概率分布辅助可视化
- `Sub_TrajectoryAnalysis.m`：主分析函数，负责导出多类图和统计结果

这部分是答辩中“仿真结果后处理与动力学统计”的核心依据。

### 4.5 `05_Utils_and_Tests`

该目录预留给辅助脚本与测试脚本。当前本地有效文件为：

- `killall.m`

如果后续需要补充测试脚本、验证脚本、绘图辅助脚本，也建议放在此目录下。

### 4.6 `Archive_Deprecated`

该目录用于存放废弃版本、旧算法或历史脚本。当前仅保留占位文件，便于后续扩展，不在主流程中调用。

## 5. 运行环境要求

建议环境如下：

- Windows 操作系统
- MATLAB
- Parallel Computing Toolbox
- 支持 MEX 的 MATLAB 编译环境

建议配置：

- 多核 CPU
- 至少 8 GB 内存
- 适合长时间批处理运算的本地工作站环境

说明：

- 当前仓库中的 `*.mexw64` 文件仅适用于 Windows 平台。
- 若后续迁移到 Linux 或 macOS，需要重新编译对应平台的 MEX 文件。

## 6. 主程序工作流程

运行主程序：

```matlab
JumpingAtMolecularFreq
```

完整流程可以概括为：

1. 初始化 MATLAB 环境与并行池。
2. 设置总仿真时间、跳跃频率、扩散系数、吸附半径等物理参数。
3. 配置相机采样时间、平均吸附时间、幂律指数、漂移速度等扫描变量。
4. 为每个重复实验生成基础缺陷地图与旋转变体。
5. 组合所有参数，形成任务列表。
6. 使用并行任务池异步执行每个参数组合的仿真。
7. 回收原始结果并清理无效点。
8. 调用轨迹分析模块生成统计图像和 `.mat` 数据文件。
9. 输出实验日志和结果目录。

## 7. 主要物理与扫描参数

主程序中当前可见的重要参数包括：

```matlab
t_total = 1000;                 % 仿真总时长 (s)
jf = 10^8;                      % 分子跳跃频率 (Hz)
D = 10^(-10);                   % 理论扩散系数 (m^2/s)
adR = 1.0;                      % 吸附半径 (nm)
L_total = 100 * 1e3;            % 模拟空间尺度 (nm)
ds = 40;                        % 缺陷平均间距 (nm)

Ts_list = [0.02];               % 相机采样时间 (s)
tmads_list = [0.05];            % 平均吸附停留时间 (s)
TimeIndex_list = [-2.5, 2.5];   % 幂律分布指数
Xshiftvelocity_list = [0.0002, 0.0008, 0.002, 0.008] * k;
Yshiftvelocity_list = [0];
DistributionModes = [1, 2, 3];  % 1幂律, 2指数, 3均匀
Repeats = 1:1;
```

其中：

- `DistributionModes` 控制吸附停留时间服从哪一类分布
- `TimeIndex_list` 在幂律分布下尤其重要
- `Xshiftvelocity_list` 和 `Yshiftvelocity_list` 控制漂移项
- `Repeats` 用于独立重复实验

## 8. 输出结果说明

程序运行时会在本地生成：

- `Simulation_Results/`
- `Experiment_Logs/`
- `codegen/`

这些目录属于运行产物或编译产物，不属于核心源码，因此已经在 `.gitignore` 中排除，不会被推送到远端仓库。

典型输出包括：

- 按时间戳命名的批次结果目录
- 每个参数组合对应的子目录
- `.mat` 分析结果文件
- 位移分布和 MSD 图像
- 本次运行的实验日志

这样整理后，远端仓库只保留“可复现源码”，而不混入体积较大的运行结果。

## 9. 轨迹分析模块说明

`04_Analysis_Modules/Sub_TrajectoryAnalysis.m` 是后处理的关键模块，主要负责：

- 同帧点合并
- 轨迹追踪
- MSD 计算
- 每步位移 `DX`、`DY` 统计
- 跳跃长度 `DL` 统计
- MSD 曲线线性拟合
- 图像导出与结果打包

答辩时可以把这一部分概括为：

“先从原始定位点重建轨迹，再从轨迹中提取扩散、跳跃和位移分布等动力学指标。”

## 10. 并行加速策略说明

本项目主要采用如下 MATLAB 并行机制：

- `parpool('local', NumCores)`：建立并行池
- `parallel.pool.Constant`：共享缺陷地图，减少重复拷贝
- `parallel.pool.DataQueue`：传递进度信息
- `parfeval`：异步提交任务
- `fetchNext`：按完成顺序回收结果

优势在于：

- 适合大规模参数扫描
- 各个任务之间相互独立，易于并行
- 可减少主线程阻塞，提高整体计算效率

## 11. 适合答辩时的项目表述方式

如果需要在答辩中简洁介绍本项目，可以使用以下表述：

> 本工作构建了一个基于 MATLAB 的界面布朗动力学高性能仿真框架，能够对单分子在异质界面上的吸附、停留、跳跃和漂移过程进行批量数值模拟，并通过并行计算显著提升参数扫描效率。仿真结果可自动完成轨迹重建、位移分布统计、跳跃长度分析及 MSD 拟合，从而为界面非高斯输运过程的机理研究提供定量支持。

如果需要更偏工程化的表述，也可以说：

> 该项目实现了“参数设置 - 并行仿真 - 轨迹分析 - 结果导出”的完整闭环，可作为后续模型扩展、参数拟合和实验对比的基础平台。

## 12. 当前版本的局限性

目前仍有以下局限：

- 主要参数仍直接写在主脚本中，尚未抽离为外部配置文件
- 注释中仍有部分历史编码问题，后续建议统一整理
- 当前测试脚本较少，自动化校验体系还不完整
- MEX 文件目前仅提供 Windows 二进制版本

## 13. 后续建议

后续可以继续完善：

- 增加统一配置文件或参数模板
- 增加小规模示例运行脚本
- 增加测试与校验脚本
- 补充跨平台 MEX 编译说明
- 增加实验参数与输出结果之间的对应清单
- 在 README 中补充公式背景与物理意义说明

## 14. 仓库地址

GitHub 仓库地址：

[https://github.com/xiao2003/Interface-Brownian-Dynamics-HPC](https://github.com/xiao2003/Interface-Brownian-Dynamics-HPC)
