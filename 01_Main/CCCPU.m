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

x0_init = (1e-6*rand+50*1e-6) * 1e9; y0_init = (1e-6*rand+50*1e-6) * 1e9;

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
    
    [DS_grid, TS_grid, TM_grid, Mx_grid, My_grid, TI_grid, Rep_grid] = ndgrid(ds, Ts, tmads_unique, Mult_X_unique, Mult_Y, TI_scan, Repeats);
    
    % 生成一个与当前网格同等大小的 Mode 矩阵
    Mode_grid = curr_Mode * ones(size(DS_grid));
    
    % 将当前模式的网格任务拼接到总 Tasks 里 (第8列为 Mode)
    Tasks_block = [DS_grid(:), TS_grid(:), TM_grid(:), Mx_grid(:), My_grid(:), TI_grid(:), Rep_grid(:), Mode_grid(:)];
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

var_str = strjoin(ctrl_vars, '_');
if isempty(var_str), var_str = 'SingleRun'; end
log_filename = sprintf('%s_ExpLog_[%s].txt', run_ts, var_str);

fileID = fopen(log_filename, 'w');
fprintf(fileID, '=======================================================\n');
fprintf(fileID, '布朗动力学并行仿真 - 实验参数日志\n');
fprintf(fileID, '=======================================================\n\n');
fprintf(fileID, '批次时间戳: %s\n环境模式: %s\n智能堆叠总任务数: %d\n调用核心: %d\n\n', ...
        run_ts, evalc('if RunOnServer, disp(''服务器''); else, disp(''本地PC''); end'), TotalTasks, NumCores);
fprintf(fileID, '[网格参数详情]\nModes = [%s]\nTs = [%s]\ntmads = [%s]\nMx = [%s]\nTI = [%s]\nRep = [%s]\n', ...
        num2str(DistributionModes), num2str(Ts), num2str(tmads_unique), num2str(Mult_X_unique), num2str(PowerLaw_TimeIndex), num2str(Repeats));
fclose(fileID);
fprintf('实验参数日志已保存至: %s\n', log_filename);

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
futures = parallel.FevalFuture.empty(TotalTasks, 0);
for i = 1:TotalTasks
    % 此时 Mode 已经包含在 Tasks 的第 8 列中，不再单独传递
    futures(i) = parfeval(pool, @SimulationTask, 1, i, dq, Tasks(i,:), x0_init, y0_init, ...
                          t_total, jf, adR, D, L_total);
end

%% --- 5. 主线程：自适应收集与监控 ---
startTime = tic;

if RunOnServer
    afterEach(dq, @(data) update_eta_cli(data, TotalTasks, startTime));
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
end

FigOffset = 100; 
for i = 1:TotalTasks
    [idx, res] = fetchNext(futures);
    p = Tasks(idx, :);
    curr_Mode = p(8); % <==== 【从矩阵中提取当前任务的分布模式】
    
    if ~RunOnServer && getappdata(hWaitbar, 'canceling')
        fprintf('\n🚨 收到终止指令！正在安全退出...\n'); cancel(futures); break;           
    end
    
    if ~isempty(res.pos) && size(res.pos, 1) > 1
        % 【传入提取出的 curr_Mode 用于分析函数】
        DataA = [p(2), p(6), res.t_r, p(3), res.k, jf, adR, FigOffset, res.nf, res.vx, res.vy, curr_Mode, p(7)];
        try, Sub_TrajectoryAnalysis(res.pos, 1000, FigOffset, p(2), DataA);
        catch ME, fprintf('[ERROR] 任务 #%d 绘图失败: %s\n', idx, ME.message); end
        
        for f_id = (1+FigOffset):(6+FigOffset), if ishandle(f_id), close(f_id); end, end
    else
        fprintf('[跳过] 任务 #%d (Mode=%d, Mx=%.1e, Rep=%d) 无有效轨迹。\n', idx, curr_Mode, p(4), p(7));
    end
end

if ~RunOnServer && isvalid(hWaitbar), close(hWaitbar); end
fprintf('\n=== 所有任务导出完成！批次: %s ===\n', run_ts);
delete(gcp('nocreate')); close all;               

% =========================================================================
% Worker 纯计算子函数
% =========================================================================
function out = SimulationTask(taskID, dq, p, x0, y0, t_tot, jf, adR, D, L)
    t_start = tic; 
    
    % <==== 【解包提取当前 Mode】
    curr_ds=p(1); curr_Ts=p(2); curr_tmads=p(3); curr_Mx=p(4); curr_My=p(5); curr_TI=p(6); curr_Rep=p(7); curr_Mode=p(8);
    
    rng(curr_Rep); XYd = rand(round(L/curr_ds)^2, 2) * L;
    tau = 1/jf; k = sqrt(2*D*tau)*1e9; vx = curr_Mx*(k/tau); vy = curr_My*(k/tau);
    cx = x0; cy = y0; tr = 0; X = []; Y = []; F = []; 
    
    nf = round(t_tot/curr_Ts);
    report_interval = max(1, round(nf / 100)); 
    
    for j = 1:nf
        dtans = [curr_Ts, curr_TI, tr, curr_tmads, k, jf, adR, 0, j, vx, vy, curr_Mode];
        [xe, ye, Xads, Yads, tr] = Sub_JumpingBetweenEachFrame_mex(cx, cy, XYd, dtans);
        cx = xe; cy = ye;
        if ~isnan(Xads(1)), X=[X; Xads']; Y=[Y; Yads']; F=[F; ones(size(Yads'))*j]; end
        if mod(j, report_interval) == 0, send(dq, [taskID, j/nf, toc(t_start)]); end
    end
    send(dq, [taskID, 1.0, toc(t_start)]); 
    valid = ~isnan(X);
    out.pos = [X(valid), Y(valid), F(valid)];
    out.t_r = tr; out.k = k; out.vx = vx; out.vy = vy; out.nf = nf;
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