# Interface Brownian Dynamics HPC

### MATLAB framework for parallel simulation and statistical analysis of jump-dwell-diffusion dynamics on heterogeneous interfaces

![MATLAB](https://img.shields.io/badge/language-MATLAB-orange)
![MEX](https://img.shields.io/badge/acceleration-MEX%20(C%2FC%2B%2B)-blue)
![Platform](https://img.shields.io/badge/platform-Windows-0078D6)
![Parallel](https://img.shields.io/badge/parallel-parpool%20%7C%20parfeval-success)
![Docs](https://img.shields.io/badge/docs-Chinese-important)

Interface Brownian Dynamics HPC is a MATLAB-based simulation project for single-molecule transport on heterogeneous interfaces. The code models the coupled process of free diffusion, defect capture, adsorption waiting, desorption, and frame-wise observation, then connects the microscopic dynamics to macroscopic observables such as trajectories, jump statistics, residence-time distributions, displacement distributions, and MSD curves.

This repository is not just a trajectory generator. It is a complete experiment pipeline that integrates:

- parameter sweep
- defect-map generation
- high-frequency MEX stepping
- binary linked-cell indexing
- asynchronous parallel scheduling
- result archiving
- post-analysis and plotting

It is designed for large parameter scans, reproducible computational experiments, paper figures, and performance-oriented HPC execution.

---

## Architecture

![Interface Brownian Dynamics HPC Architecture](assets/architecture-overview.png)

---

## 1. Scientific question

The project focuses on a class of interface transport problems where molecules do not simply execute homogeneous Brownian motion. Instead, transport is strongly affected by:

- spatially heterogeneous adsorption sites
- stochastic trapping and desorption
- long-tailed waiting-time statistics
- drift-diffusion coupling
- observation through finite camera frames

These ingredients naturally produce non-classical transport signatures, including:

- non-Gaussian displacement distributions
- intermittent stop-and-go trajectories
- anomalous jump-length statistics
- MSD curves that deviate from simple linear scaling
- strong dependence on adsorption radius, site spacing, and waiting-time law

The central goal of the codebase is therefore:

**to map microscopic adsorption and hopping rules onto measurable trajectory statistics under large-scale parameter sweeps.**

---

## 2. What the framework does

The current framework supports the following end-to-end workflow:

1. Define physical parameters and scan ranges in the main script.
2. Generate a base defect block and derive four rotated local maps.
3. Convert each local map into a linked-cell index.
4. Serialize the indexed maps into `SharedHash_*.bin` files.
5. Launch asynchronous parallel tasks with `parfeval`.
6. Let each worker memory-map the binary index and call the linked-cell MEX engine.
7. Recover trajectories, adsorption events, and per-event adsorption durations.
8. Run trajectory analysis, save `.mat` outputs, and export plots.

This gives the project two strong properties:

- the physical model is explicit and modifiable
- the execution path is optimized for large-scale repeated runs

---

## 3. Directory structure

```text
.
├── 01_Main/
│   └── JumpingAtMolecularFreq.m
├── 02_Simulation_Engine/
│   ├── Sub_JumpingBetweenEachFrame.m
│   ├── Sub_JumpingBetweenEachFrame_LinkedCell.m
│   ├── Sub_JumpingBetweenEachFrame_LinkedCell_mex.mexw64
│   ├── Sub_JumpingBetweenEachFrame_mex.m
│   └── Sub_JumpingBetweenEachFrame_mex_mex.mexw64
├── 03_Distributions/
│   ├── Sub_GenerateExponentialWithMean.m
│   ├── Sub_GeneratePowerLawWithMean.m
│   └── Sub_GenerateUniformWithMean.m
├── 04_Analysis_Modules/
│   ├── Actual_AdsorptionTime_Filtered.m
│   ├── CDF.m
│   ├── Smart_Folder_Plot.m
│   ├── Sub_JumpingAnalysis.m
│   ├── Sub_MergingLocalizationsInSameFrame.m
│   ├── Sub_ShowProbabilityDXDY.m
│   ├── Sub_TrajectoryAnalysis.m
│   └── track.m
├── 05_Utils_and_Tests/
│   ├── Do_Compile_HPC.m
│   ├── build_linkedcell_mex.m
│   └── killall.m
├── Archive_Deprecated/
│   └── .gitkeep
├── assets/
│   └── architecture-overview.png
├── .gitignore
└── README.md
```

---

## 4. Module responsibilities

### `01_Main/JumpingAtMolecularFreq.m`

This is the orchestration layer of the whole project. It is responsible for:

- physical parameter configuration
- scan-range definition
- parallel pool setup
- defect block generation
- linked-cell index construction
- binary hash export
- task-table expansion
- asynchronous dispatch and collection
- run-time progress display
- output naming and archiving

In practical terms, this file turns a scientific scan into a reproducible batch computation.

### `02_Simulation_Engine/`

This directory contains the frame-level stepping engines.

- `Sub_JumpingBetweenEachFrame_LinkedCell.m`
  Current main-path engine. Uses linked-cell indexing and block-hash map selection.
- `Sub_JumpingBetweenEachFrame_LinkedCell_mex.mexw64`
  Compiled MEX binary used for production execution on Windows.
- `Sub_JumpingBetweenEachFrame_mex.m`
  Older static-hash implementation retained for comparison and fallback.
- `Sub_JumpingBetweenEachFrame_mex_mex.mexw64`
  Compiled binary of the older path.

The key design idea is that MATLAB organizes tasks, while the MEX layer executes the high-frequency microscopic stepping.

### `03_Distributions/`

This directory controls how adsorption waiting time is sampled.

- `Sub_GeneratePowerLawWithMean.m`
  Power-law waiting-time model. The latest version handles finite-mean and truncated regimes more robustly.
- `Sub_GenerateExponentialWithMean.m`
  Exponential waiting-time model for memoryless adsorption.
- `Sub_GenerateUniformWithMean.m`
  Uniform waiting-time model used as a simple bounded control case.

These functions determine the temporal statistics of trapping, which is one of the main physical levers in the project.

### `04_Analysis_Modules/`

This directory contains the analysis and plotting pipeline.

- `Sub_TrajectoryAnalysis.m`
  Main trajectory-analysis entry.
- `Sub_MergingLocalizationsInSameFrame.m`
  Merges points falling in the same observation frame.
- `Sub_JumpingAnalysis.m`
  Jump statistics and displacement-oriented analysis.
- `Sub_ShowProbabilityDXDY.m`
  Probability visualization for displacement distributions.
- `Smart_Folder_Plot.m`
  Batch plotting script for folders of saved results.
- `Actual_AdsorptionTime_Filtered.m`
  Reconstructs the true microscopic adsorption-time distribution from saved `t_ads_history`.
- `CDF.m`
  CDF-oriented plotting helper.
- `track.m`
  Trajectory plotting utility.

### `05_Utils_and_Tests/`

Utility and maintenance scripts.

- `killall.m`
  Cleans stale parallel workers and related residues before a run.
- `Do_Compile_HPC.m`
  Compile helper for the older static-hash MEX path.
- `build_linkedcell_mex.m`
  Compile helper for the current linked-cell MEX path.

---

## 5. Physical model

The code implements a discrete-time transport model with adsorption.

### 5.1 Free motion

At the microscopic level, each free step is modeled as:

```matlab
dx = k * randn + vx;
dy = k * randn + vy;
xe = xb + dx;
ye = yb + dy;
```

where:

- `k = sqrt(2*D*tau) * 1e9`
- `D` is the diffusion coefficient
- `tau = 1/jf` is the elementary jump time
- `vx, vy` are drift terms

This is a discretized drift-diffusion process.

### 5.2 Adsorption criterion

After each tentative move, the engine finds the nearest defect candidate in the relevant local neighborhood. If the squared distance satisfies

```matlab
min_d_sq < adR^2
```

the particle is considered captured by the interface defect.

Here:

- `adR` is the effective adsorption radius
- the defect field is geometrically explicit rather than mean-field averaged

This means adsorption is controlled jointly by spatial structure and stochastic motion.

### 5.3 Waiting-time model

Once adsorption occurs, a residence time is drawn from the selected distribution model:

- power law
- exponential
- uniform

This is physically important because many anomalous transport behaviors are driven more by waiting-time statistics than by anomalous step-length statistics.

### 5.4 Residual time across observation windows

The engine tracks leftover time `t_r` when a microscopic event crosses the boundary of an observation frame. This avoids an artificial reset at each frame and preserves time continuity between consecutive observation windows.

This is essential for physically faithful frame-based simulation.

---

## 6. Spatial model and acceleration strategy

The latest architecture replaces full-map brute-force searching with a compact block-based and linked-cell-based spatial indexing scheme.

### 6.1 Base block plus four rotations

The main script first generates one square defect block of side length `L_block`. It then builds four local maps:

- original
- 90 degree rotation
- 180 degree rotation
- 270 degree rotation

This gives controlled spatial heterogeneity without storing a globally huge explicit map.

The large interface is then represented conceptually as a tiling of local blocks whose map identity is selected by a block hash.

### 6.2 Block-hash map selection

During simulation, the particle position determines a global block index:

- `bx_global`
- `by_global`

These indices are mixed with two primes and `TimeSeed` to choose one of the four local maps:

```matlab
MapIdx_i = mod(bx_global * PrimeX + by_global * PrimeY + TimeSeed, 4) + 1
```

This gives a reproducible pseudo-random spatial pattern with low storage cost.

The purpose is not cryptographic hashing. The purpose is to cheaply produce spatial heterogeneity with deterministic replay.

### 6.3 Linked-cell index

Each local map is partitioned into a regular `nx x ny` grid controlled by `cell_size`. Instead of storing a dense tensor of nearby defects, the code stores:

- `AllX`
- `AllY`
- `CellStart`
- `CellCount`

`AllX` and `AllY` are the concatenated defect coordinates after sorting by cell id. `CellStart` and `CellCount` tell the engine where the points of a given cell begin and how many there are.

This is a standard linked-cell idea adapted to the defect-search problem.

### 6.4 Binary serialization plus `memmapfile`

The indexed arrays are written into `SharedHash_Rep*_ds*_adR*.bin` files and loaded in each worker through `memmapfile`.

This choice has two practical advantages:

- workers do not need a giant MATLAB-side broadcast tensor as the main runtime data source
- the MEX engine receives sequential arrays that are much friendlier to low-level iteration

So the current acceleration strategy is:

**block-hash for macro heterogeneity + linked-cell for local search + MEX for inner-loop stepping**

---

## 7. Execution pipeline

The current main workflow in `JumpingAtMolecularFreq.m` can be read as seven stages.

### 7.1 Initialize runtime

The script clears stale state, closes old pools, and starts a fresh local parallel pool sized to the total workload while leaving some CPU headroom.

### 7.2 Define scan parameters

The script currently scans or configures variables such as:

- `t_total`
- `D`
- `jf_list`
- `adR_list`
- `ds_list`
- `Repeats`
- `DistributionModes`
- `TimeIndex_list`
- `Ts_list`
- `tmads_list`
- `Vx_ratio_list`
- `Vy_ratio_list`

These parameters collectively control geometry, dynamics, and observation conditions.

### 7.3 Pre-generate indexed defect maps

For each `Rep`, `ds`, and `adR`, the script generates the base map, derives four rotated maps, sorts points into linked cells, and writes one binary index file.

This shifts expensive preprocessing out of the innermost loop.

### 7.4 Expand the task table

All parameter combinations are packed into the `Tasks` matrix. Each row is an independent experiment unit.

This makes the simulation naturally suitable for asynchronous parallel execution.

### 7.5 Dispatch with `parfeval`

Tasks are submitted as futures rather than run in a single blocking loop. Results are collected with `fetchNext`, so fast workers are not forced to wait for slow parameter combinations.

This improves throughput and gives smooth progress reporting.

### 7.6 Run the linked-cell MEX engine

Each worker locates the relevant `SharedHash_*.bin` file, maps it into memory, reconstructs the array views, and calls the linked-cell MEX engine to simulate one frame sequence.

The engine returns:

- updated coordinates
- adsorption coordinates
- residual time
- `t_ads_history`

The explicit saving of `t_ads_history` is important because it allows later reconstruction of the actual microscopic adsorption-time distribution.

### 7.7 Analyze and archive outputs

After each task returns, the main script:

- removes invalid points
- runs analysis
- creates parameter-specific output folders
- writes result `.mat` files
- exports plots
- appends logs

This makes the repository useful as a production experiment framework, not just a prototype model.

---

## 8. Why the current framework is faster

Compared with the earliest brute-force versions, the current architecture improves performance for structural reasons.

### 8.1 Old bottleneck

The older logic relied on larger explicit defect arrays and repeated neighborhood searching in MATLAB space. That design incurred:

- large temporary arrays
- repeated nearest-neighbor scans
- more memory pressure under many workers
- more MATLAB-layer loop overhead

### 8.2 Current optimization layers

The current code reduces those costs with three changes:

1. Use a base block plus hash-selected rotated maps instead of a huge explicit global map.
2. Use linked-cell indexing so the engine checks only nearby cells instead of scanning all defects.
3. Push the microscopic stepping loop into a compiled MEX binary.

This is why the new framework is not just a code cleanup. It is a real runtime architecture upgrade.

### 8.3 Memory strategy

The current main path writes the indexed defect arrays into binary files and maps them at runtime. This reduces the dependence on repeatedly broadcasting large MATLAB arrays into every task call and keeps the worker-side data path simpler.

It does not magically eliminate all worker memory cost, but it is a much better fit for large parallel runs than the old brute-force layout.

---

## 9. Output content

The framework saves both raw and derived data.

Typical outputs include:

- trajectory coordinates
- adsorption coordinates
- jump statistics
- MSD-related quantities
- frame-wise merged localizations
- generated figures
- run logs
- `t_ads_history`

The file and folder names encode parameters such as:

- `Rep`
- distribution mode
- `TI`
- `Tads`
- `DS`
- `adR`
- `jf`
- drift-to-step ratio

This makes the output naturally traceable and suitable for later comparison across runs.

---

## 10. Analysis capabilities

The analysis layer is one of the strengths of the project.

### `Sub_TrajectoryAnalysis`

Per-run trajectory analysis and summary generation.

### `Smart_Folder_Plot`

Folder-level aggregation and batch plotting, useful after large scans have finished.

### `Actual_AdsorptionTime_Filtered`

This script is especially important in the latest workflow. It reconstructs the actual microscopic adsorption-time distribution from saved `t_ads_history`, filters and aggregates the results, and combines them with trajectory and MSD information in a unified figure.

That means the project can now compare:

- the theoretical waiting-time law used during simulation
- the actual realized adsorption-time statistics in the generated trajectories

This greatly improves interpretability.

---

## 11. How to run

1. Open MATLAB in the repository root.
2. Ensure the subfolders are on the MATLAB path.
3. Confirm that the Windows MEX binary is available.
4. Run:

```matlab
JumpingAtMolecularFreq
```

If you want to change the experimental design, edit the parameter section in:

- `01_Main/JumpingAtMolecularFreq.m`

before launching the run.

---

## 12. How to recompile the current MEX

To rebuild the linked-cell MEX used by the current main path, run:

```matlab
build_linkedcell_mex
```

If you need the older static-hash path, use:

```matlab
Do_Compile_HPC
```

Notes:

- the committed `.mexw64` binaries are Windows-specific
- Linux and macOS require recompilation
- changes in MATLAB Coder behavior or compiler toolchain may require updating the build script

---

## 13. Current innovations

From an engineering perspective, the most important innovations of the current repository are:

- MATLAB orchestration plus MEX microscopic stepping
- block-hash selection of rotated local maps
- linked-cell indexing instead of brute-force spatial search
- binary indexed map export plus worker-side `memmapfile`
- asynchronous `parfeval` scheduling instead of a purely sequential or rigid loop
- explicit saving of `t_ads_history` for post hoc adsorption-time reconstruction

From a scientific-computing perspective, the code is valuable because it ties together:

- spatial heterogeneity
- temporal heterogeneity
- drift-diffusion motion
- frame-based observation
- post-analysis reproducibility

in one coherent pipeline.

---

## 14. Practical notes

- The repository keeps some older engine files intentionally for comparison, reproducibility, and fallback.
- Temporary `SharedHash_*.bin` files are generated during execution and cleaned by the runtime logic.
- The default production path is the linked-cell MEX workflow, not the older static-hash path.
- The project is currently organized for Windows MATLAB workflows and parallel local execution.

---

## 15. Summary

Interface Brownian Dynamics HPC is a simulation-and-analysis framework for single-molecule transport on heterogeneous interfaces. Its current architecture uses:

- block-based defect generation
- hash-selected rotated maps
- linked-cell spatial indexing
- binary mapped data exchange
- MEX-accelerated microscopic stepping
- asynchronous parallel dispatch
- trajectory and adsorption-time analysis

The result is a codebase that is simultaneously:

- physically interpretable
- computationally scalable
- suitable for large parameter sweeps
- structured for paper-grade analysis and figure generation

