% =========================================================================
% 【终极全景版】支持多分布模式连跑 + 服务器自适应 + 安全区检测
% 功能：一键跑齐三种分布、智能跳过冗余任务、自动禁用服务器弹窗
% =========================================================================

%% --- 0. 环境探测与初始化 ---
clear; clc; close all;

% 【重点】：自动将当前目录下的所有子文件夹加入 MATLAB 搜索路径
addpath(genpath(pwd));
% <==== 【终极环境开关】 ====>
RunOnServer = false;  % false: 跑在本地PC (带进度条和弹窗) | true: 跑在Linux云端 (静默防崩溃)

fprintf('正在初始化计算环境...\n');
try, c = parcluster('Processes'); delete(c.Jobs); catch, end
delete(gcp('nocreate'));

if RunOnServer
    fprintf('>>> 当前模式：[云端服务器无头静默模式] <<<\n');
    set(0, 'DefaultFigureVisible', 'off'); % 强制关闭所有画图弹窗，防止 Linux X11 报错
    try, NumCores = feature('numcores'); catch, NumCores = 128; end % 自动获取服务器全核心
else
    fprintf('>>> 当前模式：[本地 PC 视窗监控模式] <<<\n');
    set(0, 'DefaultFigureVisible', 'on');
    NumCores = 26; % 本地活跃核心数
end
ShowSubTaskETA = true;

%% --- 1. 全局配置与多模式安全参数组 ---
jf = 10^(6); adR = 1.0; D = 10^(-14); L_total = 100 * (1e-6) * 1e9;

% <==== 【修改点】：直接填入你要连跑的模式！(1:幂律, 2:指数, 3:均匀)
DistributionModes = [1, 2, 3];

t_total = 1000; Ts = [0.04]; ds = [20];

% 1. 吸附时间 (各模式通用核心参数)
tmads_unique = [0.2, 0.5, 1.0, 2.0];

% 2. 漂移速度 (横跨纯扩散到强对流)
Mult_X_unique = [1e-5, 1e-4, 1e-3, 1e-2, 1e-1, 1];
Mult_Y = [0];

% 3. 幂律指数 (TI): 【绝对安全区】严格避开 (1, 2) 的发散区间！
PowerLaw_TimeIndex = [-2.0, -1.0, -0.5, 0.5, 0.9, 2.5, 5.0];

% 4. 蒙特卡洛重复次数
Repeats = [1, 2, 3,4 ,5];
SeedEnsemble = [1, 2, 3];   % 同一参数组的不同地图种子编号（可扩展）

% IID 参考起点：所有子任务统一从同一物理参考点出发，避免任务间状态继承
x0_init = 50e3;
y0_init = 50e3;

% 运行级随机盐：同参不同批次可得到不同轨迹，同时保持单批次可复现实验
rng('shuffle');
RunSalt = randi([1, 2^31-1], 1, 'uint32');

%% --- 2. 动态任务网格化 (按分布模式智能堆叠，拒绝冗余) ---
Tasks = [];
for m_idx = 1:length(DistributionModes)
    curr_Mode = DistributionModes(m_idx);

    % 智能去冗余：只有幂律(1)才需要扫描时间指数，其他模式TI设为0
    if curr_Mode == 1
        TI_scan = PowerLaw_TimeIndex;
    else
        TI_scan = 0;
    end

    [DS_grid, TS_grid, TM_grid, Mx_grid, My_grid, TI_grid, Rep_grid, Seed_grid] = ndgrid(ds, Ts, tmads_unique, Mult_X_unique, Mult_Y, TI_scan, Repeats, SeedEnsemble);

    % 生成一个与当前网格同等大小的 Mode 矩阵
    Mode_grid = curr_Mode * ones(size(DS_grid));

    % 将当前模式的网格任务拼接到总 Tasks 里 (第8列为 Mode)
    Tasks_block = [DS_grid(:), TS_grid(:), TM_grid(:), Mx_grid(:), My_grid(:), TI_grid(:), Rep_grid(:), Mode_grid(:), Seed_grid(:)];
    Tasks = [Tasks; Tasks_block];
end

TotalTasks = size(Tasks, 1);

%% --- 2.5 自动生成实验参数日志 (Log) ---
run_ts = datestr(now, 'yyyy-mm-dd-HHMMSS');
ctrl_vars = {};
if length(DistributionModes) > 1, ctrl_vars{end+1} = 'Mode'; end % 记录 Mode 是否扫描
if length(Ts) > 1, ctrl_vars{end+1} = 'Ts'; end
if length(tmads_unique) > 1, ctrl_vars{end+1} = 'Tad'; end
if length(ds) > 1, ctrl_vars{end+1} = 'ds'; end
if length(Mult_X_unique) > 1, ctrl_vars{end+1} = 'Mx'; end
if length(Mult_Y) > 1, ctrl_vars{end+1} = 'My'; end
if any(DistributionModes == 1) && length(PowerLaw_TimeIndex) > 1, ctrl_vars{end+1} = 'TI'; end
if length(Repeats) > 1, ctrl_vars{end+1} = 'Rep'; end
if length(SeedEnsemble) > 1, ctrl_vars{end+1} = 'Seed'; end

var_str = strjoin(ctrl_vars, '_');
if isempty(var_str), var_str = 'SingleRun'; end
BatchRoot = sprintf('Results_Batch_%s', run_ts);
TempTaskDir = fullfile(BatchRoot, 'TempTasks');
if ~exist(TempTaskDir, 'dir'), mkdir(TempTaskDir); end

log_filename = fullfile(BatchRoot, sprintf('%s_ExpLog_[%s].txt', run_ts, var_str));
manifest_csv = fullfile(BatchRoot, 'TaskManifest.csv');
metadata_mat = fullfile(BatchRoot, 'Batch_Metadata.mat');

fileID = fopen(log_filename, 'w');
fprintf(fileID, '=======================================================\n');
fprintf(fileID, '布朗动力学并行仿真 - 实验参数日志\n');
fprintf(fileID, '=======================================================\n\n');
fprintf(fileID, '批次时间戳: %s\n环境模式: %s\n智能堆叠总任务数: %d\n调用核心: %d\n\n', ...
        run_ts, evalc('if RunOnServer, disp(''服务器''); else, disp(''本地PC''); end'), TotalTasks, NumCores);
fprintf(fileID, '[网格参数详情]\nModes = [%s]\nTs = [%s]\ntmads = [%s]\nMx = [%s]\nTI = [%s]\nRep = [%s]\nSeedEnsemble = [%s]\n', ...
        num2str(DistributionModes), num2str(Ts), num2str(tmads_unique), num2str(Mult_X_unique), num2str(PowerLaw_TimeIndex), num2str(Repeats), num2str(SeedEnsemble));
fprintf(fileID, '\n[随机与哈希策略]\n');
fprintf(fileID, 'RunSalt = %u\n', RunSalt);
fprintf(fileID, 'MotionSeed = hash(taskID, params, RunSalt)\n');
fprintf(fileID, 'ChunkSeed = mod(MapSeedID + ix*7919 + iy + MapSeedHash*104729, 2147483646) + 1 (MapSeedHash不含Repeat)\n');
fprintf(fileID, 'ChunkSize(nm) = %.0f\nChunkNeighborRadius = %d\n', 20e3, 1);
fclose(fileID);
fprintf('实验参数日志已保存至: %s\n', log_filename);

% 保存批次元数据（便于复现实验）
BatchMeta = struct();
BatchMeta.run_ts = run_ts;
BatchMeta.RunSalt = RunSalt;
BatchMeta.DistributionModes = DistributionModes;
BatchMeta.Ts = Ts;
BatchMeta.ds = ds;
BatchMeta.tmads_unique = tmads_unique;
BatchMeta.Mult_X_unique = Mult_X_unique;
BatchMeta.Mult_Y = Mult_Y;
BatchMeta.PowerLaw_TimeIndex = PowerLaw_TimeIndex;
BatchMeta.Repeats = Repeats;
BatchMeta.SeedEnsemble = SeedEnsemble;
BatchMeta.chunk_size_nm = 20e3;
BatchMeta.chunk_neighbor_radius = 1;
save(metadata_mat, 'BatchMeta');

% 初始化任务清单 CSV
mfid = fopen(manifest_csv, 'w');
fprintf(mfid, 'TaskID,GroupID,Mode,Rep,MapSeedID,ds,Ts,tmads,Mx,My,TI,MotionSeed,MapSeedHash,RunSalt,OffsetXY_nm,TempFile\n');
fclose(mfid);

%% --- 3. 启动并行环境 ---
fprintf('正在配置 %d 核并行池...\n', NumCores);
pool = gcp('nocreate');
if isempty(pool) || pool.NumWorkers ~= NumCores
    delete(pool);
    pool = parpool('local', NumCores);
end

%% --- 4. 建立数据队列与异步提交 ---
fprintf('正在提交 %d 个任务至后台计算队列...\n', TotalTasks);
dq = parallel.pool.DataQueue;
saveQ = parallel.pool.DataQueue;
futures = parallel.FevalFuture.empty(TotalTasks, 0);
for i = 1:TotalTasks
    % 此时 Mode 已经包含在 Tasks 的第 8 列中，不再单独传递
    futures(i) = parfeval(pool, @SimulationTask, 1, i, dq, Tasks(i,:), x0_init, y0_init, ...
                          t_total, jf, adR, D, L_total, RunSalt);
end

%% --- 5. 主线程：自适应收集与监控 ---
startTime = tic;

if RunOnServer
    afterEach(dq, @(data) update_eta_cli(data, TotalTasks, startTime));
    afterEach(saveQ, @(pkg) persist_task_payload(pkg, TempTaskDir, manifest_csv, RunSalt));
else
    wb_title = '多模式全景并行监控';
    hWaitbar = waitbar(0, '正在连接后台，评估计算速度...', 'Name', wb_title);
    pos = get(hWaitbar, 'Position');
    set(hWaitbar, 'Position', [pos(1), pos(2)-100, pos(3)*1.2, pos(4)+150], 'Windowstyle', 'normal');
    cancel_cmd = 'setappdata(gcbf, ''canceling'', 1)';
    uicontrol(hWaitbar, 'Style', 'pushbutton', 'String', '取消(Cancel)', 'Position', [pos(3)*1.2 - 90, 10, 80, 25], 'Callback', cancel_cmd);
    setappdata(hWaitbar, 'canceling', 0);
    setappdata(hWaitbar, 'taskProg', zeros(1, TotalTasks));
    setappdata(hWaitbar, 'taskTime', zeros(1, TotalTasks));
    afterEach(dq, @(data) update_eta_gui(hWaitbar, data, TotalTasks, startTime, NumCores, ShowSubTaskETA));
    afterEach(saveQ, @(pkg) persist_task_payload(pkg, TempTaskDir, manifest_csv, RunSalt));
end
setappdata(0, 'SavedTaskCount', 0);

FigOffset = 100;
% 以 [ds, Ts, tmads, Mx, My, TI, Mode] 分组，将不同 Repeat 做空间偏移后系综分析
[groupValues, ~, groupIdxMap] = unique(Tasks(:, [1 2 3 4 5 6 8]), 'rows', 'stable');
numGroups = size(groupValues, 1);
GroupPL = cell(numGroups, 1);
GroupRepCount = zeros(numGroups, 1);
GroupMeta = cell(numGroups, 1);

for i = 1:TotalTasks
    [idx, res] = fetchNext(futures);
    p = Tasks(idx, :);
    curr_Mode = p(8); % <==== 【从矩阵中提取当前任务的分布模式】
    curr_MapSeedID = p(9);
    gID = groupIdxMap(idx);

    if ~RunOnServer && getappdata(hWaitbar, 'canceling')
        fprintf('\n🚨 收到终止指令！正在安全退出...\n'); cancel(futures); break;
    end

    offset_val = NaN;
    if ~isempty(res.pos) && size(res.pos, 1) > 1
        GroupRepCount(gID) = GroupRepCount(gID) + 1;
        repOrder = GroupRepCount(gID);
        offset_val = (repOrder - 1) * 1e9;

        % 轨迹附加唯一任务标签（使用 task idx，避免编码碰撞）
        pl_tmp = [res.pos, idx * ones(size(res.pos,1), 1)];
        GroupPL{gID} = [GroupPL{gID}; pl_tmp];

        if isempty(GroupMeta{gID})
            GroupMeta{gID} = struct('Ts', p(2), 'TI', p(6), 'tmads', p(3), ...
                                    'k', res.k, 'nf', res.nf, 'vx', res.vx, 'vy', res.vy, 'mode', curr_Mode);
        end
    else
        fprintf('[跳过] 任务 #%d (Mode=%d, Mx=%.1e, Rep=%d) 无有效轨迹。\n', idx, curr_Mode, p(4), p(7));
    end

    % 异步 I/O：通过 saveQ 回调落盘与写 manifest，解耦 fetch 与存储
    save_pkg = struct('task_index', idx, 'group_id', gID, 'params', p, 'result', res, 'offset_val', offset_val);
    send(saveQ, save_pkg);

    clear res save_pkg;
end

% 等待异步落盘回调全部完成
wait_tic = tic;
while getappdata(0, 'SavedTaskCount') < TotalTasks && toc(wait_tic) < 120
    pause(0.05);
end
saved_final = getappdata(0, 'SavedTaskCount');
if saved_final < TotalTasks
    error('异步落盘未完成：已保存 %d / %d，请检查 persist_task_payload 回调是否报错。', saved_final, TotalTasks);
end

% 分组后统一分析（已进行空间偏移堆叠）
for g = 1:numGroups
    if isempty(GroupPL{g}) || isempty(GroupMeta{g}), continue; end
    meta = GroupMeta{g};
    DataA = [meta.Ts, meta.TI, 0, meta.tmads, meta.k, jf, adR, FigOffset, meta.nf, meta.vx, meta.vy, meta.mode, 0];
    try
        Sub_TrajectoryAnalysis(GroupPL{g}, 1000, FigOffset, meta.Ts, DataA, BatchRoot);
    catch ME
        fprintf('[ERROR] 参数组 #%d 分析失败: %s\n', g, ME.message);
    end
    for f_id = (1+FigOffset):(6+FigOffset), if ishandle(f_id), close(f_id); end, end
end

if ~RunOnServer && isvalid(hWaitbar), close(hWaitbar); end
rmappdata(0, 'SavedTaskCount');
fprintf('\n=== 所有任务导出完成！批次: %s ===\n', run_ts);
delete(gcp('nocreate')); close all;

function persist_task_payload(pkg, TempTaskDir, manifest_csv, RunSalt)
    tempFile = fullfile(TempTaskDir, sprintf('Task_%06d.mat', pkg.task_index));
    task_payload = struct('task_index', pkg.task_index, 'params', pkg.params, 'result', pkg.result, 'RunSalt', RunSalt);
    save(tempFile, 'task_payload', '-v7.3');

    p = pkg.params;
    mfid = fopen(manifest_csv, 'a');
    fprintf(mfid, '%d,%d,%d,%d,%d,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g,%u,%u,%u,%.12g,%s\n', ...
            pkg.task_index, pkg.group_id, p(8), p(7), p(9), p(1), p(2), p(3), p(4), p(5), p(6), ...
            uint32(pkg.result.seed), uint32(pkg.result.map_seed_hash), uint32(RunSalt), pkg.offset_val, strrep(tempFile, ',', ';'));
    fclose(mfid);

    savedCount = getappdata(0, 'SavedTaskCount');
    if isempty(savedCount), savedCount = 0; end
    setappdata(0, 'SavedTaskCount', savedCount + 1);
end

% =========================================================================
% Worker 纯计算子函数
% =========================================================================
function out = SimulationTask(taskID, dq, p, x0, y0, t_tot, jf, adR, D, L, RunSalt)
    t_start = tic;

    % <==== 【解包提取当前 Mode】
    curr_ds=p(1); curr_Ts=p(2); curr_tmads=p(3); curr_Mx=p(4); curr_My=p(5); curr_TI=p(6); curr_Rep=p(7); curr_Mode=p(8); curr_MapSeedID=p(9);

    seed = compute_task_seed(taskID, p, RunSalt);
    map_seed_hash = compute_map_seed_hash(curr_MapSeedID, p, RunSalt);
    rng(seed, 'twister');

    tau = 1/jf; k = sqrt(2*D*tau)*1e9; vx = curr_Mx*(k/tau); vy = curr_My*(k/tau);
    cx = x0; cy = y0; tr = 0; X = []; Y = []; F = [];

    % 动态域扩展：20 um Chunk 按需确定性生成（含缓存）
    chunk_size_nm = 20e3;
    chunk_cache = struct('ix', {}, 'iy', {}, 'xy', {});
    local_chunk_radius = 1; % 当前块 + 8 邻块

    nf = round(t_tot/curr_Ts);
    report_interval = max(1, round(nf / 100));

    for j = 1:nf
        [XYd_local, chunk_cache] = get_local_chunk_defects(cx, cy, curr_ds, curr_MapSeedID, map_seed_hash, chunk_size_nm, local_chunk_radius, chunk_cache);

        dtans = [curr_Ts, curr_TI, tr, curr_tmads, k, jf, adR, 0, j, vx, vy, curr_Mode];
        [xe, ye, Xads, Yads, tr] = Sub_JumpingBetweenEachFrame_mex(cx, cy, XYd_local, dtans);
        cx = xe; cy = ye;
        if ~isnan(Xads(1)), X=[X; Xads']; Y=[Y; Yads']; F=[F; ones(size(Yads'))*j]; end
        if mod(j, report_interval) == 0, send(dq, [taskID, j/nf, toc(t_start)]); end
    end

    send(dq, [taskID, 1.0, toc(t_start)]);
    valid = ~isnan(X);
    out.pos = [X(valid), Y(valid), F(valid)];
    out.t_r = tr; out.k = k; out.vx = vx; out.vy = vy; out.nf = nf; out.seed = seed; out.map_seed_hash = map_seed_hash;
end

function seed = compute_task_seed(taskID, p, RunSalt)
    p_int = round(p .* [1e3, 1e6, 1e6, 1e12, 1e12, 1e6, 1, 1, 1]);
    h = uint64(1469598103934665603);
    for i = 1:numel(p_int)
        h = bitxor(h, uint64(typecast(int64(p_int(i)), 'uint64')));
        h = h * uint64(1099511628211);
    end
    h = h + uint64(taskID) * uint64(7919) + uint64(RunSalt) * uint64(104729);
    seed = double(mod(h, uint64(2^32 - 1))) + 1;
end

function map_seed_hash = compute_map_seed_hash(mapSeedID, p, RunSalt)
    % 地图哈希仅绑定“物理参数 + 分布模式 + MapSeedID”，不绑定 Repeat，
    % 以便同图多重复仅由运动噪声差异产生轨迹离散。
    p_map = p([1 2 3 4 5 6 8]);
    p_int = round(p_map .* [1e3, 1e6, 1e6, 1e12, 1e12, 1e6, 1]);
    h = uint64(2166136261);
    for i = 1:numel(p_int)
        h = bitxor(h, uint64(typecast(int64(p_int(i)), 'uint64')));
        h = h * uint64(16777619);
    end
    h = h + uint64(mapSeedID) * uint64(7919) + uint64(RunSalt) * uint64(104729);
    map_seed_hash = double(mod(h, uint64(2^31 - 2))) + 1;
end

function [XYd_local, cache] = get_local_chunk_defects(xc, yc, ds, mapSeedID, map_seed_hash, chunk_size_nm, radius_chunk, cache)
    ix0 = floor(xc / chunk_size_nm);
    iy0 = floor(yc / chunk_size_nm);
    XYd_local = zeros(0,2);

    for dix = -radius_chunk:radius_chunk
        for diy = -radius_chunk:radius_chunk
            ix = ix0 + dix;
            iy = iy0 + diy;
            cache_idx = find_chunk_cache_index(cache, ix, iy);
            if cache_idx == 0
                xy = generate_chunk_defects(ix, iy, ds, mapSeedID, map_seed_hash, chunk_size_nm);
                cache(end+1).ix = ix; %#ok<AGROW>
                cache(end).iy = iy;
                cache(end).xy = xy;
                cache_idx = numel(cache);
            end
            XYd_local = [XYd_local; cache(cache_idx).xy]; %#ok<AGROW>
        end
    end
end

function idx = find_chunk_cache_index(cache, ix, iy)
    idx = 0;
    for k = 1:numel(cache)
        if cache(k).ix == ix && cache(k).iy == iy
            idx = k;
            return;
        end
    end
end

function xy = generate_chunk_defects(ix, iy, ds, mapSeedID, map_seed_hash, chunk_size_nm)
    n_def = max(1, round((chunk_size_nm/ds)^2));
    seed_chunk = uint64(int64(mapSeedID) + int64(ix) * 7919 + int64(iy));
    seed_chunk = seed_chunk + uint64(map_seed_hash) * uint64(104729);
    seed_chunk = mod(seed_chunk, uint64(2147483646)) + 1;
    rs = RandStream('mt19937ar', 'Seed', double(seed_chunk));
    base_x = ix * chunk_size_nm;
    base_y = iy * chunk_size_nm;
    xy = rand(rs, n_def, 2) .* chunk_size_nm + [base_x, base_y];
end

% =========================================================================
% 回调 1：本地 PC 动态网格 UI 渲染
% =========================================================================
function update_eta_gui(hWaitbar, data, TotalTasks, startTime, NumCores, ShowSubTaskETA)
    if ~isvalid(hWaitbar) || getappdata(hWaitbar, 'canceling'), return; end
    taskID = data(1); fraction = data(2); elapsed_task = data(3);

    taskProg = getappdata(hWaitbar, 'taskProg'); taskTime = getappdata(hWaitbar, 'taskTime');
    taskProg(taskID) = fraction; taskTime(taskID) = elapsed_task;
    setappdata(hWaitbar, 'taskProg', taskProg); setappdata(hWaitbar, 'taskTime', taskTime);

    delta = (sum(taskProg) / TotalTasks) * 100; elapsed = toc(startTime);
    if delta > 0 && elapsed > 0, rem_time = (100 - delta) / (delta / elapsed); else, rem_time = 0; end

    active_idx = find(taskProg > 0 & taskProg < 1);
    runningCount = length(active_idx); completedCount = sum(taskProg == 1);

    active_str = ''; cols = 3;
    for k = 1:runningCount
        tid = active_idx(k); prog = taskProg(tid);
        if ShowSubTaskETA
            if prog > 0, rem_t = (1 - prog) * (taskTime(tid) / prog); else, rem_t = 0; end
            t_m = floor(rem_t / 60); t_s = floor(mod(rem_t, 60)); time_str = sprintf('(%02d:%02d)', t_m, t_s);
            active_str = sprintf('%s#%04d:%3.0f%%%7s ', active_str, tid, prog*100, time_str);
        else
            active_str = sprintf('%s#%04d:%3.0f%%   ', active_str, tid, prog*100);
        end
        if mod(k, cols) == 0 && k ~= runningCount, active_str = sprintf('%s\n', active_str); end
    end
    if isempty(active_str), active_str = '任务调度中...'; end
    h = floor(rem_time/3600); m = floor(mod(rem_time,3600)/60); s = floor(mod(rem_time,60));
    msg = sprintf('总体进度: %d/%d (%.3f%%) | 活跃核心: %d/%d\n预计仍需耗时: %02d:%02d:%02d\n--------------------------------------------------\n%s', ...
                  completedCount, TotalTasks, delta, runningCount, NumCores, h, m, s, active_str);
    waitbar(delta/100, hWaitbar, msg);
end

% =========================================================================
% 回调 2：云端 Linux 服务器防刷屏静默打印
% =========================================================================
function update_eta_cli(data, TotalTasks, startTime)
    persistent taskProg last_print_time
    if isempty(taskProg), taskProg = zeros(1, TotalTasks); end
    if isempty(last_print_time), last_print_time = tic; end

    taskProg(data(1)) = data(2);

    % 限流：距离上次打印超过 60 秒，或者有任务 100% 完成时才输出一行
    if data(2) == 1.0 || toc(last_print_time) > 60
        delta = (sum(taskProg) / TotalTasks) * 100;
        elapsed = toc(startTime);
        if delta > 0 && elapsed > 0, rem_time = (100 - delta) / (delta / elapsed); else, rem_time = 0; end

        runningCount = sum(taskProg > 0 & taskProg < 1);
        completedCount = sum(taskProg == 1);
        h = floor(rem_time/3600); m = floor(mod(rem_time,3600)/60); s = floor(mod(rem_time,60));

        fprintf('[%s] 进度: %d/%d (%.2f%%) | 活跃节点: %d | 预计剩余: %02d:%02d:%02d\n', ...
                datestr(now, 'HH:MM:SS'), completedCount, TotalTasks, delta, runningCount, h, m, s);
        last_print_time = tic;
    end
end
