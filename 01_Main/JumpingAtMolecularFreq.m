function JumpingAtMolecularFreq()
% =========================================================================
% 单分子表面跳跃动力学仿真
% =========================================================================
clc; close all;
clear persistent;
killall();

global RAM_History baseRAM; 
RAM_History = [];
if ispc
    [userMem, ~] = memory;
    baseRAM = userMem.MemUsedMATLAB / 1048576; 
else
    baseRAM = 0;
end
fprintf('>>> [%s] 正在初始化并行计算环境...\n', datestr(now, 'HH:MM:SS'));

try
    poolObj = gcp('nocreate');
    if ~isempty(poolObj), delete(poolObj); end
catch
end

PerfTestMode = true; 

%% --- [2] 实验参数配置 (Experimental Configuration) ---
startTime = tic;
startTimeStr = datestr(now, 'yyyy-mm-dd HH:MM:SS');

TimeSeed = 315231049;

t_total = 1000;             
D = 10^(-10);                
L_block = 1e4;        

% ======== 核心扫描参数矩阵 ========
jf_list     = [1e8];          % 跳跃频率扫描
adR_list    = [1.0];          % 吸附半径扫描
ds_list     = [10,20,60,100];           % 缺陷平均间距扫描    

Repeats = 1:1; 

DistributionModes = [1,2,3];           %1:幂律 2:指数 3:均匀

TimeIndex_list = [-2.5,2.5];   
                
Ts_list =[0.02];

tmads_list = [0.0008,0.0032];      
    
% --- 漂移速度与扩散步长的比例系数扫描 ---
Vx_ratio_list = [0];
Vy_ratio_list = [0];  
   
if ispc 
    timer_cmd = ['global RAM_History baseRAM; ', ...
                 'try, [uMem, ~] = memory; ', ...
                 'RAM_History = [RAM_History, max(0, (uMem.MemUsedMATLAB / 1048576) - baseRAM)]; ', ...
                 'catch, end'];
    memProfiler = timer('ExecutionMode', 'fixedRate', 'Period', 2.0, ...
        'TimerFcn', timer_cmd);
    start(memProfiler);
end

%% --- [3] 预生成缺陷地图阵列与 Linked-Cell 索引表（测试版） ---
fprintf('>>> [%s] 正在预生成基础缺陷区块与 Linked-Cell 索引表...\n', datestr(now, 'HH:MM:SS'));

cell_size = 100;
nx = ceil(L_block / cell_size);
ny = ceil(L_block / cell_size);

fprintf('>>> Linked-Cell参数: L_block=%g | cell_size=%g | nx=%d | ny=%d\n', ...
    L_block, cell_size, nx, ny);

for Rep = Repeats
    rng(Rep + TimeSeed, 'twister'); 
    InitPositions(Rep, :) = (1e-6 * rand(1, 2) + 50e-6) * 1e9;
    
    for adR_val = adR_list
        for ds_val = ds_list
            
            rng(Rep + TimeSeed, 'twister'); 
            Ndefect_block = round(L_block / ds_val);
            Npts = Ndefect_block^2;
            valid_L = L_block - 2 * adR_val; 
            
            Map1 = rand(Npts, 2) * valid_L + adR_val; 
            Map2 = [Map1(:, 2), L_block - Map1(:, 1)];             
            Map3 = [L_block - Map1(:, 1), L_block - Map1(:, 2)];   
            Map4 = [L_block - Map1(:, 2), Map1(:, 1)];             
            Maps = {Map1, Map2, Map3, Map4};
            
            AllX_cell = cell(1,4);
            AllY_cell = cell(1,4);
            CellStart = zeros(nx, ny, 4, 'uint32');
            CellCount = zeros(nx, ny, 4, 'uint32');
            
            maxBaseCellCount_allMaps = 0;
            totalPts_allMaps = 0;
            
            for MapIdx = 1:4
                Xd = Maps{MapIdx}(:,1);
                Yd = Maps{MapIdx}(:,2);
                
                ix = floor(Xd / cell_size) + 1;
                iy = floor(Yd / cell_size) + 1;
                
                ix(ix < 1) = 1; ix(ix > nx) = nx;
                iy(iy < 1) = 1; iy(iy > ny) = ny;
                
                cell_id = uint32(sub2ind([nx, ny], double(ix), double(iy)));
                
                [cell_id_sorted, order] = sort(cell_id);
                Xd_sorted = Xd(order);
                Yd_sorted = Yd(order);
                
                AllX_cell{MapIdx} = Xd_sorted;
                AllY_cell{MapIdx} = Yd_sorted;
                totalPts_allMaps = totalPts_allMaps + numel(Xd_sorted);
                
                if ~isempty(cell_id_sorted)
                    change_pos = [1; find(diff(double(cell_id_sorted)) ~= 0) + 1];
                    change_pos = change_pos(:);
                    start_pos  = change_pos;
                    end_pos    = [change_pos(2:end) - 1; numel(cell_id_sorted)];
                    counts     = end_pos - start_pos + 1;
                    unique_ids = cell_id_sorted(start_pos);
                
                    maxCount_map = max(counts);
                
                    for u = 1:length(unique_ids)
                        cid = unique_ids(u);
                        s = start_pos(u);
                        c = counts(u);
                
                        [ix0, iy0] = ind2sub([nx, ny], double(cid));
                        CellStart(ix0, iy0, MapIdx) = uint32(s);
                        CellCount(ix0, iy0, MapIdx) = uint32(c);
                    end
                
                    maxBaseCellCount_allMaps = max(maxBaseCellCount_allMaps, maxCount_map);
                end
            end
            
            LenMap = uint32(cellfun(@numel, AllX_cell));
            OffsetMap = uint32([0, cumsum(double(LenMap(1:3)))]);
            TotalLen = sum(double(LenMap));
            
            AllX = zeros(TotalLen, 1, 'double');
            AllY = zeros(TotalLen, 1, 'double');
            
            for MapIdx = 1:4
                s0 = double(OffsetMap(MapIdx)) + 1;
                e0 = s0 + double(LenMap(MapIdx)) - 1;
                AllX(s0:e0) = AllX_cell{MapIdx};
                AllY(s0:e0) = AllY_cell{MapIdx};
                
                nonzero_mask = CellStart(:,:,MapIdx) > 0;
                offset_u32 = uint32(OffsetMap(MapIdx));
                CellStart(:,:,MapIdx) = CellStart(:,:,MapIdx) + offset_u32 .* uint32(nonzero_mask);
            end
            
            rho = Npts / (valid_L^2);
            phi = rho * pi * adR_val^2;
            
            fprintf('>>> [Rep=%d | ds=%g | adR=%g] Npts(singleMap)=%d | TotalPts(allMaps)=%d | rho=%.4e | phi=%.4e | BaseMax(all)=%d\n', ...
                Rep, ds_val, adR_val, Npts, TotalLen, rho, phi, maxBaseCellCount_allMaps);
            
            binFileName = sprintf('SharedHash_Rep%d_ds%g_adR%g.bin', Rep, ds_val, adR_val);
            fid = fopen(binFileName, 'w');
            fwrite(fid, uint64(TotalLen), 'uint64');     
            fwrite(fid, AllX(:), 'double');
            fwrite(fid, AllY(:), 'double');
            fwrite(fid, CellStart(:), 'uint32');
            fwrite(fid, CellCount(:), 'uint32');
            fclose(fid);
            
            fileInfo = dir(binFileName);
            fprintf('>>> 已写入: %s | %.2f MB\n', binFileName, fileInfo.bytes / 1048576);
            
            clear Maps AllX AllY AllX_cell AllY_cell CellStart CellCount;
        end
    end
end

cleanupObj = onCleanup(@() delete('SharedHash_*.bin'));

successCount = 0;

%% --- [4] 任务解耦与分发 ---
Tasks = [];
for Rep = Repeats
    x0 = InitPositions(Rep, 1);
    y0 = InitPositions(Rep, 2);
    for DistMode = DistributionModes
        for Ts = Ts_list
            for tm_ads = tmads_list
                
                if DistMode == 1 
                    actual_TI_list = TimeIndex_list;
                else             
                    actual_TI_list = 0; 
                end
                
                for TI = actual_TI_list
                    for jf = jf_list
                        for adR = adR_list
                            for ds = ds_list
                                for vx_ratio = Vx_ratio_list
                                    for vy_ratio = Vy_ratio_list
                                        Tasks = [Tasks; Ts, tm_ads, TI, vx_ratio, vy_ratio, DistMode, Rep, x0, y0, jf, adR, ds];
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

TotalTasks = size(Tasks, 1); 
if TotalTasks == 0, error('任务生成失败！'); end

Tasks = Tasks(randperm(TotalTasks), :);

MaxPhysicalCores = feature('numcores'); 
NumCores = min(TotalTasks, max(1, MaxPhysicalCores - 2));
fprintf('>>> [%s] 任务总数: %d | 分配核心数: %d \n', datestr(now, 'HH:MM:SS'), TotalTasks, NumCores);

pool = gcp('nocreate');
if isempty(pool) || pool.NumWorkers ~= NumCores
    if ~isempty(pool), delete(pool); end 
    pool = parpool('local', NumCores);
end

setappdata(0, 'taskProg', zeros(1, TotalTasks)); 
setappdata(0, 'lastMsgLen', 0); 
dq = parallel.pool.DataQueue;
afterEach(dq, @(data) local_update_progress_console(double(data), TotalTasks, startTime));
futures = parallel.FevalFuture.empty(TotalTasks, 0);

fprintf('>>> [%s] 仿真任务下发完成，开始实时监控...\n', datestr(now, 'HH:MM:SS'));
fprintf('------------------------------------------------------------\n');

for i = 1:TotalTasks
    futures(i) = parfeval(pool, @Worker_JumpingTask, 1, i, dq, Tasks(i,:), ...
        t_total, D, TimeSeed, L_block, cell_size, nx, ny);
end

%% --- [5] 结果异步回收与智能归档  ---
baseResultDir = 'Simulation_Results';
if ~exist(baseResultDir, 'dir'), mkdir(baseResultDir); end
runID = datestr(now, 'yyyymmdd_HHMMSS');
mainRunDir = fullfile(baseResultDir, ['Task_' runID]);
if ~exist(mainRunDir, 'dir'), mkdir(mainRunDir); end
DistNames = {'PowerLaw', 'Exp', 'Uniform'}; 

fprintf('>>> 数据归档路径: %s\n', mainRunDir);

for i = 1:TotalTasks
    try
        [idx, res] = fetchNext(futures);
    catch ME
        fprintf('\n[FETCH-ERROR] 结果回收失败: %s\n', ME.message);
        if ~isempty(ME.cause)
            fprintf('>>> 崩溃原因: %s\n', ME.cause{1}.message);
        end
        continue;
    end
    
    p = Tasks(idx, :);
    curr_Ts = p(1); curr_tmads = p(2); curr_TI = p(3); 
    curr_vx_ratio = p(4); curr_vy_ratio = p(5); 
    curr_DistMode = p(6); curr_Rep = p(7);
    curr_jf = p(10); curr_adR = p(11); curr_ds = p(12);
    
    if isfield(res, 'pos') && ~isempty(res.pos)
        pos = res.pos;
        valid_idx = ~isnan(pos(:,1));
        positionlist = pos(valid_idx, :); 
        t_ads_history = res.t_ads_history(valid_idx); % 提取真实的吸附时间
        
        if size(positionlist, 1) > 2
            DTRACK = 1000; FigN = 0; 
            current_k = res.k;
            curr_vx = curr_vx_ratio * current_k;
            curr_vy = curr_vy_ratio * current_k;
            
            DataTrans_Analysis = [curr_Ts, curr_TI, res.t_r, curr_tmads, current_k, curr_jf, curr_adR, FigN, 0, curr_vx, curr_vy];
            
            try
                cDist = DistNames{curr_DistMode};
                subdirName = sprintf('Rep%d_%s_TI%.1f_Tads%.4f_DS%g_adR%g_jf%g_Ts%g_ratio_%gk', ...
                                     curr_Rep, cDist, curr_TI, curr_tmads, curr_ds, curr_adR, curr_jf, curr_Ts, curr_vx_ratio);
                subDirPath = fullfile(mainRunDir, subdirName);
                if ~exist(subDirPath, 'dir'), mkdir(subDirPath); end
                
                filePrefix = subdirName;
                
                if PerfTestMode
                    matFilePath = fullfile(subDirPath, [filePrefix, '.mat']);
                    save(matFilePath, 'positionlist', 't_ads_history', 'p', 'res', '-v7.3');
                else
                    [SD, DX, DY, DL, analysis_results] = Sub_TrajectoryAnalysis(positionlist, DTRACK, FigN, curr_Ts, DataTrans_Analysis, subDirPath, filePrefix);
                    matFilePath = fullfile(subDirPath, [filePrefix, '.mat']);
                    save(matFilePath, 'positionlist', 't_ads_history', 'SD', 'DX', 'DY', 'DL', 'p', 'res', 'analysis_results', '-v7.3');
                end

                successCount = successCount + 1;

                fprintf('\n[OK] Task %d/%d -> %s\n', idx, TotalTasks, subdirName); 
                
            catch ME
                fprintf('\n[ERROR] Task %d 处理失败: %s\n', idx, ME.message);
            end
        else
            fprintf('\n[SKIP] Task %d: 轨迹点数不足。\n', idx);
        end
    else
        fprintf('\n[SKIP] Task %d: 返回数据为空。\n', idx);
    end
    
    setappdata(0, 'lastMsgLen', 0); 
    clear res pos positionlist t_ads_history SD DX DY DL analysis_results; 
    
    if mod(i, 10) == 0
        drawnow; 
    end
end
fprintf('\n');

%% --- [6] 实验日志导出与系统扫尾 ---
if ispc && exist('memProfiler', 'var') && isvalid(memProfiler)
    stop(memProfiler); 
    if ~isempty(RAM_History)
        avgNetRAM = mean(RAM_History); peakNetRAM = max(RAM_History);
    else
        avgNetRAM = 0; peakNetRAM = 0;
    end
    delete(memProfiler);
else
    avgNetRAM = 0; peakNetRAM = 0;
end

endTimeStr = datestr(now, 'yyyy-mm-dd HH:MM:SS');
totalDuration = toc(startTime);

binFiles = dir('SharedHash_*.bin');
if ~isempty(binFiles)
    payloadSizeMB = sum([binFiles.bytes]) / 1048576;
else
    payloadSizeMB = 0;
end

allVars = whos;
totalWorkspaceMB = sum([allVars.bytes]) / 1048576;

logDir = 'Experiment_Logs';
if ~exist(logDir, 'dir'), mkdir(logDir); end
logFileName = sprintf('SimLog_%s.txt', runID);
logFilePath = fullfile(logDir, logFileName);
fid = fopen(logFilePath, 'w');
fprintf(fid, '============================================================\n');
fprintf(fid, '单分子跳跃动力学 - 仿真报告 \n');
fprintf(fid, '============================================================\n');
fprintf(fid, '【1. 运行系统信息】\n');
fprintf(fid, '  %-28s: %s\n', '运行 ID', runID);
fprintf(fid, '  %-28s: %d\n', '计算核心数', NumCores);
fprintf(fid, '  %-28s: %s\n', '开始时间', startTimeStr);
fprintf(fid, '  %-28s: %s\n', '结束时间', endTimeStr);
fprintf(fid, '  %-28s: %.2f 分钟\n', '总耗时', totalDuration/60);
fprintf(fid, '  %-28s: %d\n', '总任务数', TotalTasks);
fprintf(fid, '  %-28s: %d\n', '完成任务数', successCount);
fprintf(fid, '  %-28s: %s\n', '数据存储位置', fullfile(pwd, mainRunDir));
fprintf(fid, '============================================================\n');
fprintf(fid, '【2. 核心物理常量】\n');
fprintf(fid, '  %-28s: %g s\n', '仿真总时长 (t_total)', t_total);
fprintf(fid, '  %-28s: %g m^2/s\n', '理论扩散系数 (D)', D);
fprintf(fid, '  %-28s: %g nm\n', '基础地图大小 (L_block)', L_block);
fprintf(fid, '============================================================\n');
fprintf(fid, '【3. 离散化与扫描参数阵列】\n');
fprintf(fid, '  %-28s: %s\n', '分布模式 (DistModes)', mat2str(DistributionModes));
fprintf(fid, '  %-28s: %s\n', '重复实验次数 (Repeats)', mat2str(Repeats));
fprintf(fid, '  %-28s: %s s\n', '相机采样时间 (Ts_list)', mat2str(Ts_list));
fprintf(fid, '  %-28s: %s s\n', '平均吸附时间 (tmads_list)', mat2str(tmads_list));
fprintf(fid, '  %-28s: %s\n', '分布指数 (TI_list)', mat2str(TimeIndex_list));
fprintf(fid, '  %-28s: %s\n', '频率扫描 (jf_list)', mat2str(jf_list));
fprintf(fid, '  %-28s: %s nm\n', '半径扫描 (adR_list)', mat2str(adR_list));
fprintf(fid, '  %-28s: %s nm\n', '间距扫描 (ds_list)', mat2str(ds_list));
fprintf(fid, '  %-28s: %s\n', 'X方向漂移比率 (Vx_ratio)', mat2str(Vx_ratio_list));
fprintf(fid, '  %-28s: %s\n', 'Y方向漂移比率 (Vy_ratio)', mat2str(Vy_ratio_list));
fprintf(fid, '============================================================\n');
fprintf(fid, '【4. 随机种子与空间哈希引擎参数】\n');
fprintf(fid, '  %-28s: %d\n', '时间种子 (TimeSeed)', TimeSeed);
fprintf(fid, '  %-28s: Rep + TimeSeed\n', '基础地图种子 (RNG Seed)');
fprintf(fid, '  %-28s: %g nm\n', '基础地图大小 (L_block)', L_block);
fprintf(fid, '  %-28s: 73856093\n', '空间哈希质数X (PrimeX)');
fprintf(fid, '  %-28s: 19349663\n', '空间哈希质数Y (PrimeY)');
fprintf(fid, '  %-28s: mod(Bx * PrimeX + By * PrimeY + TimeSeed, 4) + 1\n', '区块调度映射函数');
fprintf(fid, '============================================================\n');
fprintf(fid, '【5. 算力与内存性能评估】\n');
fprintf(fid, '  %-28s: %.2f MB\n', 'CSR哈希表体积 (Hash Payload)', payloadSizeMB);
fprintf(fid, '  %-28s: %.2f MB\n', '代码变量总空间 (Workspace)', totalWorkspaceMB);
if ispc
    fprintf(fid, '  %-28s: %.2f MB\n', 'MATLAB 系统基线内存 (Base)', baseRAM);
    fprintf(fid, '  %-28s: %.2f MB\n', '算法动态净消耗平均 (Avg Net)', avgNetRAM);
    fprintf(fid, '  %-28s: %.2f MB\n', '算法动态净消耗峰值 (Peak Net)', peakNetRAM);
end
fprintf(fid, '============================================================\n');
fclose(fid);

rmappdata(0, 'taskProg');
rmappdata(0, 'lastMsgLen');

warning('off', 'all'); 
delete(pool); 
try
    myCluster = parcluster('Processes');
    delete(myCluster.Jobs);
catch
    try
        myCluster = parcluster('local');
        delete(myCluster.Jobs);
    catch
    end
end
warning('on', 'all'); 

delete('SharedHash_*.bin');
clear global RAM_History baseRAM;
fprintf('>>> 扫尾工作完成，临时文件已清理。\n');
end

% =========================================================================
% Worker: 独立运算核心 
% =========================================================================
function out = Worker_JumpingTask(taskID, dq, p, t_tot, D, TimeSeed, L_block, cell_size, nx, ny)
    Ts       = p(1); 
    tm_ads   = p(2); 
    TI       = p(3);
    vx_ratio = p(4);
    vy_ratio = p(5); 
    DistMode = p(6); 
    Rep      = p(7);
    x0       = p(8); 
    y0       = p(9);
    jf       = p(10); 
    adR      = p(11); 
    ds       = p(12);
    
    tau = 1 / jf;
    k = sqrt(2 * D * tau) * 1e9;
    vx = vx_ratio * k;
    vy = vy_ratio * k;
    
    binFileName = sprintf('SharedHash_Rep%d_ds%g_adR%g.bin', Rep, ds, adR);
    
    fid = fopen(binFileName, 'r');
    TotalLen = fread(fid, 1, 'uint64');
    fclose(fid);
    
    m = memmapfile(binFileName, 'Offset', 8, 'Format', {
        'double', [double(TotalLen), 1], 'AllX';
        'double', [double(TotalLen), 1], 'AllY';
        'uint32', [nx, ny, 4], 'CellStart';
        'uint32', [nx, ny, 4], 'CellCount'
    }, 'Writable', false);
    
    AllX = m.Data.AllX;
    AllY = m.Data.AllY;
    CellStart = m.Data.CellStart;
    CellCount = m.Data.CellCount;
    
    cx = x0; 
    cy = y0; 
    tr = 0; 
    nf = round(t_tot / Ts); 
    report_step = max(1, round(nf / 20)); 
    
    chunk = 200000; 
    X_buf = zeros(chunk, 1, 'double');
    Y_buf = zeros(chunk, 1, 'double');
    T_buf = zeros(chunk, 1, 'double'); % 新增：吸附时间缓存区
    F_buf = zeros(chunk, 1, 'uint32'); 
    cursor = 0; 
    
    for j = 1:nf
        args = [Ts, TI, tr, tm_ads, k, jf, adR, 0, j, vx, vy, DistMode];
        
        % 接收真实的 Tads 数组输出
        [xe, ye, Xa_frame, Ya_frame, tr, Ta_frame] = Sub_JumpingBetweenEachFrame_LinkedCell_mex( ...
                        cx, cy, AllX, AllY, CellStart, CellCount, args, TimeSeed, ...
                        L_block, cell_size, int32(nx), int32(ny));
     
        cx = xe;
        cy = ye;
        
        if ~isnan(Xa_frame(1))
            nNew = length(Xa_frame);
            if cursor + nNew > length(X_buf)
                new_size = length(X_buf) + chunk;
                X_buf(new_size, 1) = 0;
                Y_buf(new_size, 1) = 0;
                T_buf(new_size, 1) = 0; % 同步扩容
                F_buf(new_size, 1) = 0;
            end
            
            X_buf(cursor+1:cursor+nNew) = Xa_frame';
            Y_buf(cursor+1:cursor+nNew) = Ya_frame';
            T_buf(cursor+1:cursor+nNew) = Ta_frame'; % 填入真实时间
            F_buf(cursor+1:cursor+nNew) = uint32(j);
            cursor = cursor + nNew;
        end
        
        if mod(j, report_step) == 0
            send(dq, double([taskID, j/nf]));
        end
    end
    
    send(dq, double([taskID, 1.0]));
    
    out.pos = [X_buf(1:cursor), Y_buf(1:cursor), double(F_buf(1:cursor))];
    out.t_ads_history = T_buf(1:cursor); % 打包输出
    out.t_r = tr;
    out.k = k;
    
    clear m AllX AllY CellStart CellCount;
end

function local_update_progress_console(data, total, startTime)
    data = double(data);
    if numel(data) < 2
        return;
    end
    prog = getappdata(0, 'taskProg');
    if isempty(prog) || numel(prog) ~= total
        prog = zeros(1, total);
    end
    taskID = round(data(1));
    frac   = data(2);
    if taskID < 1 || taskID > total
        return;
    end
    frac = max(0, min(1, frac));
    prog(taskID) = frac;
    setappdata(0, 'taskProg', prog);
    len = getappdata(0, 'lastMsgLen');
    if isempty(len) || len == 0
        fprintf('\n');
        len = 0;
    else
        fprintf(repmat('\b', 1, len));
    end
    delta = sum(prog) / total;
    elap  = toc(startTime);
    doneCount   = sum(prog >= 1.0);
    activeNodes = sum(prog > 0 & prog < 1.0);
    if delta > 0
        remTime = elap * (1 - delta) / delta;
        etaStr = sprintf('%02d:%02d:%02d', ...
            floor(remTime/3600), ...
            floor(mod(remTime,3600)/60), ...
            floor(mod(remTime,60)));
    else
        etaStr = '--:--:--';
    end
    barLen = 20;
    filled = floor(delta * barLen);
    barStr = [repmat('>', 1, filled), repmat(' ', 1, barLen - filled)];
    msg = sprintf('Progress: [%s] %5.1f%% | Done: %d/%d | Active: %d | ETA: %s', ...
        barStr, delta*100, doneCount, total, activeNodes, etaStr);
    fprintf('%s', msg);
    setappdata(0, 'lastMsgLen', length(msg));
end