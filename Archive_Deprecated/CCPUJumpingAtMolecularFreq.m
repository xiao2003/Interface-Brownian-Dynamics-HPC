% =========================================================================
% 旗舰版主程序：自定义核心数 + 碎片化 ETA + 全景子任务监控
% =========================================================================

%% --- 0. 环境初始化与残留清理 ---
clear; clc; close all;
fprintf('正在初始化环境并清理残留作业...\n');
try, c = parcluster('Processes'); delete(c.Jobs); catch, end
delete(gcp('nocreate')); 

%% --- 1. 全局配置与模式开关 ---
NumCores = 26;             % <==== 【修改点1】：手动设置活跃核心数 (将影响启动和UI显示)
ShowSubTaskETA = true;     % <==== 【修改点2】：是否在UI中显示每个子任务的剩余时间 (true/false)
Enable_QuickTest = false;  % 测试模式开关 (false: 1000s生产模式; true: 1s极速测试)

DistributionMode = 1; 
jf = 10^(6); adR = 1.0; D = 10^(-14); L_total = 100 * (1e-6) * 1e9; 

if Enable_QuickTest
    fprintf('\n>>> [测试模式] t_total = 1s <<<\n\n');
    t_total = 1; Ts = [0.04]; tmads_unique = [1.0]; ds = [20];                                        
    Mult_X_unique = [1e-1]; Mult_Y = [0]; PowerLaw_TimeIndex = [-100]; Repeats = [1]; 
else
    fprintf('\n>>> [生产模式] t_total = 1000s <<<\n\n');
    t_total = 1000; Ts = [0.04]; 
    tmads_unique = [0.2, 0.3, 0.5, 0.7, 0.9, 1.0]; 
    ds = [20]; 
    Mult_X_unique =[1e-5, 1e-4, 1e-3, 1e-2, 1e-1, 0, 1]; %[0];
    Mult_Y = [0];                  
    PowerLaw_TimeIndex = [0.5];%[-2.0, -1.0, -0.5, 0.5, 0.99, 2.01];
    Repeats = [1, 2, 3]; 
end

x0_init = (1e-6*rand+50*1e-6) * 1e9; y0_init = (1e-6*rand+50*1e-6) * 1e9;
if DistributionMode == 1, TI_scan = PowerLaw_TimeIndex; else, TI_scan = 0; end
[DS_grid, TS_grid, TM_grid, Mx_grid, My_grid, TI_grid, Rep_grid] = ndgrid(ds, Ts, tmads_unique, Mult_X_unique, Mult_Y, TI_scan, Repeats);

Tasks = [DS_grid(:), TS_grid(:), TM_grid(:), Mx_grid(:), My_grid(:), TI_grid(:), Rep_grid(:)];
TotalTasks = size(Tasks, 1);
% =========================================================================
% 2.5 自动生成实验参数日志 (Log)
% =========================================================================
run_ts = datestr(now, 'yyyy-mm-dd-HHMMSS'); % 全局批次时间戳

% 动态提取处于“扫描控制”状态的变量名（即数组长度大于 1 的参数）
ctrl_vars = {};
if length(Ts) > 1, ctrl_vars{end+1} = 'Ts'; end
if length(tmads_unique) > 1, ctrl_vars{end+1} = 'Tad'; end
if length(ds) > 1, ctrl_vars{end+1} = 'ds'; end
if length(Mult_X_unique) > 1, ctrl_vars{end+1} = 'Mx'; end
if length(Mult_Y) > 1, ctrl_vars{end+1} = 'My'; end
if DistributionMode == 1 && length(PowerLaw_TimeIndex) > 1, ctrl_vars{end+1} = 'TI'; end
if length(Repeats) > 1, ctrl_vars{end+1} = 'Rep'; end

% 将控制变量名拼接为字符串，如果都没扫那就是 SingleRun
var_str = strjoin(ctrl_vars, '_');
if isempty(var_str), var_str = 'SingleRun'; end

% 拼接带有时间戳和控制变量的日志文件名
log_filename = sprintf('%s_ExpLog_[%s].txt', run_ts, var_str);

% 写入详细参数到 txt 文件
fileID = fopen(log_filename, 'w');
fprintf(fileID, '=======================================================\n');
fprintf(fileID, '布朗动力学并行仿真 - 实验参数日志\n');
fprintf(fileID, '=======================================================\n\n');
fprintf(fileID, '批次时间戳: %s\n', run_ts);
fprintf(fileID, '动态识别到的控制变量: %s\n', var_str);
fprintf(fileID, '去重后总任务数 (TotalTasks): %d\n', TotalTasks);
fprintf(fileID, '调用的并行核心数 (NumCores): %d\n\n', NumCores);

fprintf(fileID, '[全局基础参数]\n');
fprintf(fileID, 'DistributionMode = %d (1:幂律, 2:指数, 3:均匀)\n', DistributionMode);
fprintf(fileID, 't_total = %d s\n', t_total);
fprintf(fileID, 'jf = %g Hz\n', jf);
fprintf(fileID, 'adR = %g nm\n', adR);
fprintf(fileID, 'D = %g\n', D);
fprintf(fileID, 'L_total = %g nm\n\n', L_total);

fprintf(fileID, '[网格参数详情]\n');
fprintf(fileID, 'Ts = [%s]\n', num2str(Ts));
fprintf(fileID, 'tmads_unique = [%s]\n', num2str(tmads_unique));
fprintf(fileID, 'ds = [%s]\n', num2str(ds));
fprintf(fileID, 'Mult_X_unique = [%s]\n', num2str(Mult_X_unique));
fprintf(fileID, 'Mult_Y = [%s]\n', num2str(Mult_Y));
fprintf(fileID, 'PowerLaw_TimeIndex = [%s]\n', num2str(PowerLaw_TimeIndex));
fprintf(fileID, 'Repeats = [%s]\n\n', num2str(Repeats));
fclose(fileID);

fprintf('实验参数日志已保存至: %s\n', log_filename);

%% --- 3. 启动并行环境 ---
fprintf('正在配置 %d 核并行池...\n', NumCores);
pool = gcp('nocreate');
if isempty(pool) || pool.NumWorkers ~= NumCores
    delete(pool);
    pool = parpool(NumCores); 
end

%% --- 4. 建立数据队列与异步提交 ---
fprintf('正在提交 %d 个任务至后台计算队列...\n', TotalTasks);
dq = parallel.pool.DataQueue;
futures = parallel.FevalFuture.empty(TotalTasks, 0);

for i = 1:TotalTasks
    futures(i) = parfeval(pool, @SimulationTask, 1, i, dq, Tasks(i,:), x0_init, y0_init, ...
                          DistributionMode, t_total, jf, adR, D, L_total);
end

%% --- 5. 主线程：收集结果、画图、导出 ---
% 0. 动态定义标题
if Enable_QuickTest
    wb_title = '[测试模式]计算与绘图监控';
else
    wb_title = '[生产模式]长效计算监控';
end

% 1. 先创建基础窗口
hWaitbar = waitbar(0, '正在连接后台，评估计算速度...', 'Name', wb_title);

% 2. 调整窗口尺寸（拉伸空间以容纳子任务网格）
pos = get(hWaitbar, 'Position');
set(hWaitbar, 'Position', [pos(1), pos(2)-100, pos(3)*1.2, pos(4)+150]); 

% 3. 后期注入“取消按钮”回调函数，并初始化所有进度数据
set(hWaitbar, 'Windowstyle', 'normal'); % 确保窗口可以被调节
cancel_cmd = 'setappdata(gcbf, ''canceling'', 1)';
uicontrol(hWaitbar, 'Style', 'pushbutton', 'String', '取消(Cancel)', ...
          'Position', [pos(3)*1.2 - 90, 10, 80, 25], ...
          'Callback', cancel_cmd);

setappdata(hWaitbar, 'canceling', 0); 
setappdata(hWaitbar, 'taskProg', zeros(1, TotalTasks)); 
setappdata(hWaitbar, 'taskTime', zeros(1, TotalTasks));

startTime = tic;
% 绑定回调，将配置传入 UI 刷新器
afterEach(dq, @(data) update_eta(hWaitbar, data, TotalTasks, startTime, NumCores, ShowSubTaskETA));

FigOffset = 100; 
for i = 1:TotalTasks
    [idx, res] = fetchNext(futures);
    p = Tasks(idx, :);
    
    if getappdata(hWaitbar, 'canceling')
        fprintf('\n🚨 收到终止指令！正在安全退出...\n'); cancel(futures); break;           
    end
    
    if isempty(res.pos) || size(res.pos, 1) < 2
        fprintf('[跳过] 任务 #%d (Mx=%.1e, Rep=%d) 无有效轨迹。\n', idx, p(4), p(7));
    else
        DataA = [p(2), p(6), res.t_r, p(3), res.k, jf, adR, FigOffset, res.nf, res.vx, res.vy, DistributionMode, p(7)];
        try, Sub_TrajectoryAnalysis(res.pos, 1000, FigOffset, p(2), DataA);
        catch ME, fprintf('任务 #%d 绘图失败: %s\n', idx, ME.message); end
        
        for f_id = (1+FigOffset):(6+FigOffset)
            if ishandle(f_id), close(f_id); end
        end
    end
    fprintf('✅ 任务出列: Mx=%.1e, TI=%g, Rep=%d\n', p(4), p(6), p(7));
end

if isvalid(hWaitbar), close(hWaitbar); end
fprintf('\n=== 正在释放资源... ===\n'); delete(gcp('nocreate')); close all;               
fprintf('所有任务导出完成！批次: %s\n', run_ts);

% =========================================================================
% Worker 纯计算子函数
% =========================================================================
function out = SimulationTask(taskID, dq, p, x0, y0, Mode, t_tot, jf, adR, D, L)
    t_start = tic; % 【新增】：记录该 Worker 的启动时间
    
    curr_ds=p(1); curr_Ts=p(2); curr_tmads=p(3); curr_Mx=p(4); curr_My=p(5); curr_TI=p(6); curr_Rep=p(7);
    rng(curr_Rep); XYd = rand(round(L/curr_ds)^2, 2) * L;
    tau = 1/jf; k = sqrt(2*D*tau)*1e9; vx = curr_Mx*(k/tau); vy = curr_My*(k/tau);
    cx = x0; cy = y0; tr = 0; X = []; Y = []; F = []; 
    
    nf = round(t_tot/curr_Ts);
    report_interval = max(1, round(nf / 100)); 
    
    for j = 1:nf
        dtans = [curr_Ts, curr_TI, tr, curr_tmads, k, jf, adR, 0, j, vx, vy, Mode];
        [xe, ye, Xads, Yads, tr] = Sub_JumpingBetweenEachFrame_mex(cx, cy, XYd, dtans);
        cx = xe; cy = ye;
        if ~isnan(Xads(1)), X=[X; Xads']; Y=[Y; Yads']; F=[F; ones(size(Yads'))*j]; end
        
        % 【修改点3】：连同进度和当前Worker的消耗时间一起发回去
        if mod(j, report_interval) == 0
            send(dq, [taskID, j/nf, toc(t_start)]);
        end
    end
    send(dq, [taskID, 1.0, toc(t_start)]); 
    
    valid = ~isnan(X);
    out.pos = [X(valid), Y(valid), F(valid)];
    out.t_r = tr; out.k = k; out.vx = vx; out.vy = vy; out.nf = nf;
end

% =========================================================================
% 数据队列回调函数：集成子任务 ETA 与动态网格排版
% =========================================================================
function update_eta(hWaitbar, data, TotalTasks, startTime, NumCores, ShowSubTaskETA)
    if ~isvalid(hWaitbar) || getappdata(hWaitbar, 'canceling'), return; end
    
    taskID = data(1); fraction = data(2); elapsed_task = data(3);
    
    taskProg = getappdata(hWaitbar, 'taskProg');
    taskTime = getappdata(hWaitbar, 'taskTime');
    taskProg(taskID) = fraction;
    taskTime(taskID) = elapsed_task;
    setappdata(hWaitbar, 'taskProg', taskProg);
    setappdata(hWaitbar, 'taskTime', taskTime);
    
    delta = (sum(taskProg) / TotalTasks) * 100; 
    elapsed = toc(startTime);
    if delta > 0 && elapsed > 0
        rem_time = (100 - delta) / (delta / elapsed); 
    else
        rem_time = 0;
    end
    
    active_idx = find(taskProg > 0 & taskProg < 1); 
    runningCount = length(active_idx);
    completedCount = sum(taskProg == 1);
    
    % --- 子任务网格排版 ---
    active_str = '';
    cols = 5; 
    if ShowSubTaskETA, cols = 3; end % 如果要显示子时间，就改成3列防止文字出界
    
    for k = 1:runningCount
        tid = active_idx(k);
        prog = taskProg(tid);
        
        if ShowSubTaskETA
            % 单个任务的剩余时间推算
            if prog > 0
                rem_t = (1 - prog) * (taskTime(tid) / prog);
            else
                rem_t = 0;
            end
            t_m = floor(rem_t / 60); t_s = floor(mod(rem_t, 60));
            time_str = sprintf('(%02d:%02d)', t_m, t_s);
            % 排版格式: #0001: 45%(12:05)
            active_str = sprintf('%s#%04d:%3.0f%%%7s ', active_str, tid, prog*100, time_str);
        else
            active_str = sprintf('%s#%04d:%3.0f%%   ', active_str, tid, prog*100);
        end
        
        % 换行控制
        if mod(k, cols) == 0 && k ~= runningCount
            active_str = sprintf('%s\n', active_str);
        end
    end
    if isempty(active_str), active_str = '任务调度中...'; end
    
    h = floor(rem_time/3600); m = floor(mod(rem_time,3600)/60); s = floor(mod(rem_time,60));
    
    msg = sprintf(['总体进度: %d/%d (%.3f%%) | 活跃核心: %d/%d\n', ...
                   '预计仍需耗时: %02d:%02d:%02d\n', ...
                   '--------------------------------------------------\n', ...
                   '%s'], ...
                  completedCount, TotalTasks, delta, runningCount, NumCores, h, m, s, active_str);
    waitbar(delta/100, hWaitbar, msg);
end