#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def read_from_commit(commit: str, relpath: str) -> str:
    out = subprocess.run([
        'git', 'show', f'{commit}:{relpath}'
    ], cwd=ROOT, text=True, capture_output=True, check=True)
    return out.stdout

BASE_COMMIT = '1745e98'
baseline = {
    'main': read_from_commit(BASE_COMMIT, '01_Main/CCCPU.m'),
    'mex': read_from_commit(BASE_COMMIT, '02_Simulation_Engine/Sub_JumpingBetweenEachFrame_mex.m'),
    'analysis': read_from_commit(BASE_COMMIT, '04_Analysis_Modules/Sub_TrajectoryAnalysis.m'),
}

files = {
    'main': ROOT / '01_Main' / 'CCCPU.m',
    'mex': ROOT / '02_Simulation_Engine' / 'Sub_JumpingBetweenEachFrame_mex.m',
    'analysis': ROOT / '04_Analysis_Modules' / 'Sub_TrajectoryAnalysis.m',
    'readme': ROOT / 'README.md',
    'dist_pow': ROOT / '03_Distributions' / 'Sub_GeneratePowerLawWithMean.m',
    'dist_exp': ROOT / '03_Distributions' / 'Sub_GenerateExponentialWithMean.m',
    'dist_uni': ROOT / '03_Distributions' / 'Sub_GenerateUniformWithMean.m',
    'track': ROOT / '04_Analysis_Modules' / 'track.m',
    'merge': ROOT / '04_Analysis_Modules' / 'Sub_MergingLocalizationsInSameFrame.m',
}

text = {k: p.read_text(encoding='utf-8') for k,p in files.items()}

checks = [
    ("1.IID-fixed-start", "x0_init = 50e3" in text['main'] and "y0_init = 50e3" in text['main']),
    ("1.IID-indep-task", "parfeval(pool, @SimulationTask" in text['main']),
    ("1.IID-chunk-seed", ("MapSeedHash" in text['main'] or "map_seed_hash" in text['main']) and "generate_chunk_defects" in text['main']),
    ("1.IID-map-hash-not-repeat-bound", "p_map = p([1 2 3 4 5 6 8])" in text['main']),

    ("2.offset-in-analysis", "if size(PL,2) >= 4" in text['analysis'] and "shift_nm = (ridx - 1) * 1e9" in text['analysis']),
    ("2.offset-anomaly-guard", "DL > 1e8" in text['analysis'] or "DL_flat > 1e8" in text['analysis']),
    ("2.offset-unique-tag-no-collision", "pl_tmp = [res.pos, idx * ones(size(res.pos,1), 1)]" in text['main'] and "combined_id" not in text['main']),

    ("3.dynamic-chunk-size", "chunk_size_nm = 20e3" in text['main']),
    ("3.dynamic-chunk-neighbor", "local_chunk_radius = 1" in text['main']),
    ("3.dynamic-chunk-hash", (re.search(r"ix\s*\*\s*7919", text['main']) is not None) and (("MapSeedHash" in text['main']) or ("map_seed_hash" in text['main']))),

    ("4.async-save-queue", "saveQ = parallel.pool.DataQueue" in text['main']),
    ("4.async-save-callback", "afterEach(saveQ" in text['main'] and "persist_task_payload" in text['main']),
    ("4.async-save-timeout-guard", "异步落盘未完成" in text['main']),
    ("4.async-save-cleanup", "rmappdata(0, 'SavedTaskCount')" in text['main']),

    ("5.linked-cell-index", "ukeys" in text['mex'] and "starts" in text['mex'] and "ends" in text['mex']),
    ("5.linked-cell-9-neigh", "nearest_dist_sq_9cell" in text['mex']),

    ("6.adaptive-dt", "dt = 50 * tjmp" in text['mex'] and "dt = tjmp" in text['mex']),
    ("6.diffusion-rescale", "sqrt(dt / tjmp)" in text['mex']),

    ("7.modular-path", "addpath(genpath(pwd))" in text['main']),
    ("7.batch-folder", "Results_Batch_" in text['main'] and "TempTasks" in text['main']),

    # 原有功能回归（对照仓库主代码路径）
    ("R1.main-calls-mex", "Sub_JumpingBetweenEachFrame_mex" in text['main']),
    ("R2.main-calls-analysis", "Sub_TrajectoryAnalysis" in text['main']),
    ("R3.mex-distribution-generators", "Sub_GeneratePowerLawWithMean" in text['mex'] and "Sub_GenerateExponentialWithMean" in text['mex'] and "Sub_GenerateUniformWithMean" in text['mex']),
    ("R4.analysis-uses-track", "T = track(positionlist,DTRACK);" in text['analysis']),
    ("R5.readme-docs-hpc", "HPC" in text['readme'] and "Chunk" in text['readme']),
    ("R6.distribution-files-exist", files['dist_pow'].exists() and files['dist_exp'].exists() and files['dist_uni'].exists()),
    ("R7.main-grid-scan-still-present", "DistributionModes" in text['main'] and "ndgrid" in text['main']),
    ("R8.analysis-export-still-present", "savefig" in text['analysis'] and "print(fig_num, '-djpeg', '-r300'" in text['analysis']),
    ("R9.mex-distmode-switch-still-present", "switch DistMode" in text['mex'] and "case 1" in text['mex'] and "case 2" in text['mex'] and "case 3" in text['mex']),
    ("R10.analysis-core-files-exist", files['track'].exists() and files['merge'].exists()),
    ("R11.main-server-local-switch", "RunOnServer = false" in text['main'] and "DefaultFigureVisible" in text['main']),
    ("R12.mode-specific-TI-scan", "if curr_Mode == 1" in text['main'] and "TI_scan = 0" in text['main']),
    ("R13.analysis-backward-compatible-batchroot", "if nargin < 6 || isempty(BatchRoot)" in text['analysis']),

    ("R14.manifest-header-schema", "TaskID,GroupID,Mode,Rep,MapSeedID,ds,Ts,tmads,Mx,My,TI,MotionSeed,MapSeedHash,RunSalt,OffsetXY_nm,TempFile" in text['main']),
    ("R15.manifest-row-write-schema", "fprintf(mfid" in text['main'] and "%u,%u,%u,%.12g,%s" in text['main']),
    ("R16.baseline-main-core-flow-retained", "parfeval" in baseline['main'] and "fetchNext" in baseline['main'] and "parfeval" in text['main'] and "fetchNext" in text['main']),
    ("R17.baseline-mex-core-switch-retained", "switch DistMode" in baseline['mex'] and "switch DistMode" in text['mex']),
    ("R18.baseline-analysis-track-merge-retained", "Sub_MergingLocalizationsInSameFrame" in baseline['analysis'] and "Sub_MergingLocalizationsInSameFrame" in text['analysis'] and "T = track(positionlist,DTRACK);" in baseline['analysis'] and "T = track(positionlist,DTRACK);" in text['analysis']),
    ("R19.iid-start-forwarded-to-worker", "parfeval(pool, @SimulationTask" in text['main'] and "x0_init, y0_init" in text['main']),
    ("R20.worker-uses-local-state-not-shared-endpoint", "cx = x0; cy = y0;" in text['main'] and "cx = xe; cy = ye;" in text['main']),
    ("R21.chunk-seed-formula-has-mapseed-and-hash", "mapSeedID" in text['main'] and "seed_chunk = uint64(int64(mapSeedID) + int64(ix) * 7919 + int64(iy));" in text['main'] and "seed_chunk = seed_chunk + uint64(map_seed_hash) * uint64(104729);" in text['main']),
    ("R22.async-save-is-decoupled-from-fetch", "send(saveQ, save_pkg);" in text['main'] and "clear res save_pkg;" in text['main']),
    ("R23.manifest-columns-match-write-arity", text['main'].count('TaskID,GroupID,Mode,Rep,MapSeedID,ds,Ts,tmads,Mx,My,TI,MotionSeed,MapSeedHash,RunSalt,OffsetXY_nm,TempFile') == 1 and text['main'].count("%d,%d,%d,%d,%d,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g,%u,%u,%u,%.12g,%s") == 1),
    ("R24.baseline-distribution-generators-still-referenced", "Sub_GeneratePowerLawWithMean" in baseline['mex'] and "Sub_GenerateExponentialWithMean" in baseline['mex'] and "Sub_GenerateUniformWithMean" in baseline['mex'] and "Sub_GeneratePowerLawWithMean" in text['mex'] and "Sub_GenerateExponentialWithMean" in text['mex'] and "Sub_GenerateUniformWithMean" in text['mex']),
    ("R25.baseline-modular-addpath-still-present", "addpath(genpath(pwd))" in baseline['main'] and "addpath(genpath(pwd))" in text['main']),
    ("R26.baseline-server-switch-compat", "RunOnServer" in baseline['main'] and "RunOnServer" in text['main'] and "DefaultFigureVisible" in text['main']),
    ("R27.offset-applied-before-merge-track", "shift_nm = (ridx - 1) * 1e9" in text['analysis'] and "Sub_MergingLocalizationsInSameFrame" in text['analysis'] and text['analysis'].find("shift_nm = (ridx - 1) * 1e9") < text['analysis'].find("Sub_MergingLocalizationsInSameFrame")),
    ("R28.large-jump-warning-threshold", "超大跳跃(>1e8 nm)" in text['analysis'] and "DL_flat > 1e8" in text['analysis']),
    ("R29.async-barrier-before-analysis", text['main'].find("while getappdata(0, 'SavedTaskCount') < TotalTasks") < text['main'].find("for g = 1:numGroups")),
    ("R30.batch-artifacts-defined", "Batch_Metadata.mat" in text['main'] and "TaskManifest.csv" in text['main'] and "TempTasks" in text['main']),
    ("R31.no-merge-conflict-markers-main", re.search(r"^<<<<<<< |^=======$|^>>>>>>> ", text['main'], re.M) is None),
    ("R32.no-merge-conflict-markers-core", re.search(r"^<<<<<<< |^=======$|^>>>>>>> ", text['mex'], re.M) is None and re.search(r"^<<<<<<< |^=======$|^>>>>>>> ", text['analysis'], re.M) is None and re.search(r"^<<<<<<< |^=======$|^>>>>>>> ", text['readme'], re.M) is None),
]

failed = []
for name, ok in checks:
    print(f"{'PASS' if ok else 'FAIL'}  {name}")
    if not ok:
        failed.append(name)

print("\nSummary:")
print(f"  total={len(checks)} pass={len(checks)-len(failed)} fail={len(failed)}")
if failed:
    print("  failed: " + ", ".join(failed))
    raise SystemExit(1)
