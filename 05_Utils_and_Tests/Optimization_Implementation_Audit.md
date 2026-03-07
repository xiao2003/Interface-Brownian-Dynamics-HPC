# 优化算法实现审计（第十七轮：7 项要求 + 分支冲突防护检查）

> 审计范围：`01_Main/CCCPU.m`、`02_Simulation_Engine/Sub_JumpingBetweenEachFrame_mex.m`、`04_Analysis_Modules/*`、`03_Distributions/*`、`README.md`。
> 结论：7 项优化持续满足；并通过“初始功能回归”静态核验（52/52）。

---

## 1) 任务解耦与独立初值控制（IID）

- 固定参考起点：`x0_init=50e3, y0_init=50e3`。
- 并行任务独立执行，无末态继承链。
- `MotionSeed` 与 `MapSeedHash` 分离，且地图哈希不绑定 Repeat。

**判定：✅ 已实现。**

## 2) 空间偏移堆叠系综平均（Spatial Offset Stacking）

- 分析模块内部执行 `1e9 nm` 偏移再 track。
- 超大跳跃告警（`DL > 1e8`）用于跨轨迹误连检测。
- 标签使用唯一 `idx`，避免编码碰撞。

**判定：✅ 已实现。**

## 3) 动态域扩展（Dynamic Domain Expansion）

- 20 μm chunk 按需生成（当前位置 + 8 邻块）。
- 决定性 hash + worker 缓存复用，回访地形一致。

**判定：✅ 已实现。**

## 4) 异步 I/O 实时落盘（Asynchronous I/O）

- `saveQ + afterEach(saveQ, @persist_task_payload)` 回调落盘。
- 主线程只发送保存包，不直接写盘。
- `SavedTaskCount` 完成屏障 + 超时报错 + 清理 appdata。

**判定：✅ 已实现。**

## 5) Linked-Cell 近邻索引

- MEX 内 cell-list 建表；查询限制在 9 邻域。

**判定：✅ 已实现。**

## 6) 自适应多尺度积分（Adaptive Time-stepping）

- 距离感知步长切换（`tjmp` ~ `50*tjmp`）。
- `sqrt(dt/tjmp)` 扩散缩放保持统计一致。

**判定：✅ 已实现。**

## 7) 模块化与批次化收纳

- `addpath(genpath(pwd))` 保持跨目录调用。
- 批次目录统一收纳日志、manifest、metadata、TempTasks、分析图表/mat。

**判定：✅ 已实现。**

---

## 初始功能回归（持续增强）

为满足“对照初始代码确保原有功能正确”，额外校验：

- 主控仍保留 server/local 模式切换（`RunOnServer` 与 `DefaultFigureVisible`）。
- 主控仍调用 MEX 核心与分析主路径。
- MEX 仍保留三分布分支（幂律/指数/均匀）。
- 分析关键文件仍存在：`track.m` 与 `Sub_MergingLocalizationsInSameFrame.m`。
- 发生器文件仍存在：`03_Distributions/Sub_Generate*.m`。
- 分析导出路径（`.mat/.fig/.jpg`）仍在。

---

## 自动复核脚本（持续增强）

- 脚本：`05_Utils_and_Tests/check_optimization_requirements.py`
- 当前检查项：52 条（含初始提交对照、IID/异步/偏移顺序一致性、批次产物完整性与冲突标记防护检查）。
- 当前结果：`pass=52, fail=0`。


## 与初始代码对照（新增）

- 检查脚本直接读取初始提交 `1745e98` 的主控/MEX/分析文件（`git show 1745e98:<path>`），并核对关键主流程符号在当前代码仍存在。
- 对照项包括：主控并行调度主流程（`parfeval/fetchNext`）、MEX 分布分支主结构（`switch DistMode`）、分析中的 merge+track 主路径。
- 同时增加 `TaskManifest` 头部与行写入格式的结构一致性检查，确保异步落盘产物可追溯。


## 本轮新增静态核验点（R19~R24）

- IID 入口一致性：检查 `x0_init/y0_init` 确实从主控传入 worker，并在 worker 内使用本地状态 `cx/cy` 迭代。
- Chunk 哈希一致性：检查 chunk seed 同时绑定 `mapSeedID` 与 `map_seed_hash`，并包含 `ix*7919 + iy`。
- 异步解耦一致性：检查 fetch 主循环通过 `send(saveQ, ...)` 投递，且随后清理临时变量，避免主线程持有累积对象。
- Manifest 架构一致性：检查 header 与行写入模板都唯一存在，确保字段数匹配与可追溯导出稳定。
- 初始版本对照增强：继续要求当前 MEX 保留初始版本三分布发生器调用路径。


## 本轮新增静态核验点（R25~R30）

- 与初始版本对照：确认 `addpath(genpath(pwd))` 与 server/local 开关兼容主结构持续存在。
- 偏移顺序正确性：确认 1e9nm 逻辑偏移发生在 merge/track 之前，避免跨重复误连。
- 超大跳跃守卫：确认 `DL_flat > 1e8` 的异常提示逻辑仍存在。
- 异步完成屏障顺序：确认 `SavedTaskCount` 等待循环在分组分析前执行。
- 批次收纳完整性：确认 `Batch_Metadata.mat`、`TaskManifest.csv`、`TempTasks` 三类批次产物定义保留。


## 本轮新增静态核验点（R31~R32）

- 冲突标记防护：在 `01_Main/CCCPU.m` 中检查是否残留 `<<<<<<< / ======= / >>>>>>>` 三类 merge 冲突标记。
- 核心模块防护：在 `Sub_JumpingBetweenEachFrame_mex.m`、`Sub_TrajectoryAnalysis.m` 与 `README.md` 中执行同类冲突标记扫描。
- 目的：在与 `main` 合并时，避免“看似可运行但残留冲突标记”导致的隐性错误进入分支。
