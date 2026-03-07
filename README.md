# 界面非高斯过程的布朗动力学仿真引擎

本项目用于模拟固液界面离子/质子的反常扩散输运过程，支持多种停留时间分布模型、并行批处理、可复现实验随机种子和面向 HPC 的性能优化流程。

---

## 1. 项目目标与适用场景

该引擎面向以下研究需求：

- **反常扩散机制研究**：评估幂律/指数/均匀停留时间对轨迹统计量（MSD、跳跃长度等）的影响。
- **高通量参数扫描**：在多个参数维度（如 `tmads`、`Mx`、`TI`、`Repeat`、`SeedEnsemble`）上进行并行网格仿真。
- **可重复性验证**：通过 `RunSalt`、`MotionSeed`、`MapSeedHash`、`TaskManifest.csv`、`Batch_Metadata.mat` 完整记录仿真来源与随机性控制。
- **服务器大规模运行**：支持本地可视化模式与云端静默模式切换，降低内存峰值和 I/O 阻塞风险。

---

## 2. 核心能力概览

### 2.1 多模式动力学

支持 3 类吸附时间调制模型：

- **Mode=1**：幂律分布（Power-law）
- **Mode=2**：指数分布（Exponential）
- **Mode=3**：均匀分布（Uniform）

在主控中通过 `DistributionModes = [1,2,3]` 组合运行，可一键完成多模式批次扫描。

### 2.2 确定性随机化与任务解耦

- 每个子任务从统一物理参考起点（`x0_init=50e3`, `y0_init=50e3`）开始，避免“后任务继承前任务末态”。
- 使用 `compute_task_seed` 生成任务级运动噪声种子（`MotionSeed`）。
- 使用 `compute_map_seed_hash` 生成地图哈希（`MapSeedHash`），且**不绑定 Repeat**，便于同图多次独立重复。
- 通过 `SeedEnsemble` 实现同一参数组的多地图种子并行统计。

### 2.3 动态域扩展（Dynamic Domain Expansion）

- 地图按 `20 μm` 区块（Chunk）按需生成，不再预构建全局大图。
- 当前块 + 8 邻块局部加载，worker 内部缓存重用。
- Chunk 由确定性哈希生成，粒子回访同一区块可复现同一地形。

### 2.4 异步落盘与批次管理

- 主线程用 `saveQ = parallel.pool.DataQueue` + `afterEach` 将任务结果异步写盘。
- 每个任务实时保存为 `TempTasks/Task_*.mat`，并追加写入 `TaskManifest.csv`。
- 通过 `SavedTaskCount` 屏障确保退出前全部异步写入完成。
- 统一输出 `Results_Batch_<timestamp>/` 批次目录，包含日志、清单、元数据、图表和分析文件。

### 2.5 MEX 引擎性能优化

- **Linked-Cell 索引**：缺陷查询从全量扫描切换到粒子所在 cell 的 9 邻域检索。
- **自适应多尺度时间步进**：远场大步长快进、近场细步长求解。
- **扩散项重标度**：按 `sqrt(dt/tjmp)` 缩放，保证步长变化下统计一致性。

### 2.6 空间偏移堆叠分析

- 在 `Sub_TrajectoryAnalysis` 中对重复实验施加 `1e9 nm` 逻辑偏移后再送入 track。
- 避免跨重复轨迹误连接。
- 提供超大跳跃告警（`DL > 1e8`）用于检测误连风险。

---

## 3. 目录结构

```text
01_Main/                  # 主控：参数网格、并行调度、异步落盘、批次管理
02_Simulation_Engine/     # 核心跳跃引擎（含 MEX 优化）
03_Distributions/         # 幂律/指数/均匀分布发生器
04_Analysis_Modules/      # 轨迹合并、track、MSD 与统计分析
05_Utils_and_Tests/       # 审计文档与自动检查脚本
```

---

## 4. 快速开始

### 4.1 环境准备

- MATLAB（建议支持 Parallel Computing Toolbox）
- 多核 CPU（本地或服务器）

> 若在 Linux 服务器无图形环境运行，请将主控中的 `RunOnServer = true`，自动关闭图窗。

### 4.2 运行入口

主脚本：

- `01_Main/CCCPU.m`

建议流程：

1. 根据实验目标调整 `DistributionModes`、`Ts`、`tmads_unique`、`Mult_X_unique`、`PowerLaw_TimeIndex`、`Repeats`、`SeedEnsemble`。
2. 设置 `RunOnServer`（本地可视化/服务器静默）。
3. 执行 `CCCPU.m`。
4. 在 `Results_Batch_<ts>/` 中查看批次输出。

---

## 5. 关键参数说明（主控）

- `RunOnServer`：运行模式开关（本地 / 服务器）
- `NumCores`：并行核心数
- `DistributionModes`：分布模式列表
- `Repeats`：同参数重复次数
- `SeedEnsemble`：同参数地图种子集合
- `x0_init`, `y0_init`：IID 统一起点
- `RunSalt`：批次随机盐（区分批次随机化）
- `chunk_size_nm`：动态域区块尺寸（默认 `20e3 nm`）
- `local_chunk_radius`：邻域区块半径（默认 `1`，即 9 宫格）

---

## 6. 输出文件说明

每次运行生成 `Results_Batch_<timestamp>/`，典型内容包括：

- `*_ExpLog_[...].txt`：批次日志（参数与随机策略）
- `Batch_Metadata.mat`：批次元信息结构体
- `TaskManifest.csv`：任务级可追溯清单
- `TempTasks/Task_XXXXXX.mat`：每个任务的原始结果快照
- `Trajectory_Analysis/`（或相关分析目录）：统计结果与图像（`.mat/.fig/.jpg`）

---

## 7. 自动审计与回归检查

项目提供静态检查脚本：

- `05_Utils_and_Tests/check_optimization_requirements.py`

用途：

- 审查 7 类优化是否仍存在并保持一致。
- 对照初始提交关键主流程，防止“优化过程中丢失原有功能”。
- 检查批次清单、异步屏障、偏移顺序等实现约束。

运行方式：

```bash
python 05_Utils_and_Tests/check_optimization_requirements.py
```

审计说明文档：

- `05_Utils_and_Tests/Optimization_Implementation_Audit.md`

---

## 8. 常见运行建议

- **大规模任务优先服务器静默模式**：减少图形开销与潜在 X11 问题。
- **优先保留异步落盘机制**：避免主线程阻塞和内存累积。
- **先小规模冒烟，再全量并行**：先验证参数组合、输出目录与分析路径。
- **保持 manifest 与 metadata**：便于后续复现实验与论文可追溯性说明。

---


## 9. 分支冲突处理建议（与 main 合并时）

若 GitHub 提示以下文件有冲突：

- `README.md`
- `05_Utils_and_Tests/Optimization_Implementation_Audit.md`
- `05_Utils_and_Tests/check_optimization_requirements.py`

建议使用命令行流程：

```bash
git fetch origin
git status --short
git merge origin/main
# 手工编辑冲突文件，删除 <<<<<<< ======= >>>>>>> 标记
python 05_Utils_and_Tests/check_optimization_requirements.py
rg -n "^(<<<<<<< |=======|>>>>>>> )" README.md 05_Utils_and_Tests/Optimization_Implementation_Audit.md 05_Utils_and_Tests/check_optimization_requirements.py
git add README.md 05_Utils_and_Tests/Optimization_Implementation_Audit.md 05_Utils_and_Tests/check_optimization_requirements.py
git commit -m "resolve: merge conflicts with main"
```

> 说明：本仓库检查脚本已包含冲突标记扫描规则，可在提交前自动拦截冲突残留。

---

## 10. 作者

Wang Beiyan  
信息力学与感知工程学院，西安电子科技大学


## 11. 最终推送前检查清单（建议）

```bash
git fetch --all --prune
git status --short
python 05_Utils_and_Tests/check_optimization_requirements.py
rg -n "^(<<<<<<< |=======|>>>>>>> )" README.md 05_Utils_and_Tests/Optimization_Implementation_Audit.md 05_Utils_and_Tests/check_optimization_requirements.py
git push origin <your-branch>
```

- 若 `push` 被拒绝且你确认要覆盖远端同名分支，使用：
  - `git push --force-with-lease origin <your-branch>`
- 推送成功后到 PR 页面确认：
  - `Checks` 通过
  - 冲突提示消失

---
