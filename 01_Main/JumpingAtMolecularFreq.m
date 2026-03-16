function JumpingAtMolecularFreq()
% =========================================================================
% 单分子表面跳跃动力学仿真
% 核心优势: 
% 1. 消除 Worker 节点的随机数开销与主客节点间的海量通信拥堵
% 2. 引入动态持续性进度条与 ETA 监控
% 3. 精确调用 Coder 编译的底层 C/C++ 引擎 (mex_mex)
% 4. 全自动结果提取、NaN清理、轨迹分析 (Sub_TrajectoryAnalysis)
% 5. 基于物理参数的动态 .mat 文件命名与分类归档
% =========================================================================

%codegen Sub_JumpingBetweenEachFrame_mex -args {0.0, 0.0, coder.typeof(0.0, [150, 100, 100, 4], [false, false, false, false]), coder.typeof(0.0, [150, 100, 100, 4], [false, false, false, false]), coder.typeof(0.0, [100, 100, 4], [false, false, false]), coder.typeof(0.0, [1, 12], [false, false]), 0.0} -report

clc; close all;
clear persistent; 
fprintf('>>> [%s] 正在初始化并行计算环境...\n', datestr(now, 'HH:MM:SS'));

% --- [1] 系统初始化与环境自校验 ---
try
    poolObj = gcp('nocreate');
    if ~isempty(poolObj)
        delete(poolObj); 
    end
catch
end

% NumCores = min(10, feature('numcores')); % 预留系统核心避免系统卡顿
% 
% fprintf('>>> [%s] 并行池启动中 (分配核心数: %d)...\n', datestr(now, 'HH:MM:SS'), NumCores);
% pool = parpool('local', NumCores);       

%% --- [2] 实验参数配置 (Experimental Configuration) ---
startTime = tic;
startTimeStr = datestr(now, 'yyyy-mm-dd HH:MM:SS');

% =========================================================================
% 性能测试开关
% true  = 极速纯计算模式 (屏蔽一切画图与后处理，专测底层算力，仅保存坐标流)
% false = 完整分析模式 (计算 MSD、扩散系数 SD，并导出所有统计图表与全量矩阵)
PerfTestMode = false; 
% =========================================================================

% 核心物理常量
t_total = 10000;             % 仿真总时长 (s)
jf = 10^8;                 % 分子跳跃频率 (Hz)
D = 10^(-10);                % 理论扩散系数 (m^2/s)
adR = 1.0;                  % 吸附半径 (nm)
L_total = 100 * 1e3;        % 空间总尺寸 100um -> 100,000 nm
ds = 40;                    % 缺陷平均间距 (nm)

tau = 1/jf;
k = sqrt(2*D*tau) * 1e9; 

% 离散化与时空尺度扫描阵列
DistributionModes = [1,2,3];   % 1: 幂律分布, 2: 指数分布, 3: 均匀分布 (先测一种避免任务过多)
Repeats = 1:1;                 % 重复实验次数 (亦作为独立地图的样本数)

Ts_list = [0.02];              % 相机采样时间 (s)
tmads_list = [0.01,0.05,0.20,0.50];           % 平均吸附时间 (s)
TimeIndex_list = [-2.5,2.5];       % 幂律分布指数 (TI) 
Xshiftvelocity_list =[0];% [0, 1e-4, 5e-4, 1e-3, 5e-3, 1e-2, 5e-2, 0.1]*k;% X方向漂移速度 (nm/s) - 0为纯扩散对照组
Yshiftvelocity_list =[0];     % Y方向漂移速度 (nm/s)

%% --- [3] 预生成缺陷地图阵列与静态哈希表 (极速静态查表优化) ---
fprintf('>>> [%s] 正在预生成基础缺陷区块与静态哈希映射表...\n', datestr(now, 'HH:MM:SS'));

L_block = 10000; % 基础区块的边长 (nm)
Ndefect_block = round(L_block/ds); 
TimeSeed = str2double(datestr(now, 'mmddHHMMSS'));

% 预计算静态哈希表参数
cell_size = 100;
nx = ceil(L_block / cell_size);
ny = ceil(L_block / cell_size);
max_pts_per_nbhd = 150; % 每个3x3局部网格预留的最大缺陷数

StaticHashXCell = cell(1, max(Repeats));
StaticHashYCell = cell(1, max(Repeats));
StaticHashCountCell = cell(1, max(Repeats));
InitPositions = zeros(max(Repeats), 2);

for Rep = Repeats
    rng(Rep + TimeSeed, 'twister'); 
    
    % 1. 生成带护城河的基础地图
    valid_L = L_block - 2 * adR; 
    Map1 = rand(Ndefect_block^2, 2) * valid_L + adR; 
    Map2 = [Map1(:, 2), L_block - Map1(:, 1)];             
    Map3 = [L_block - Map1(:, 1), L_block - Map1(:, 2)];   
    Map4 = [L_block - Map1(:, 2), Map1(:, 1)];             
    Maps = {Map1, Map2, Map3, Map4};
    
    % 2. 核心加速：构建 O(1) 静态哈希查询表
    HashX = zeros(max_pts_per_nbhd, nx, ny, 4);
    HashY = zeros(max_pts_per_nbhd, nx, ny, 4);
    HashCount = zeros(nx, ny, 4);
    
    for MapIdx = 1:4
        Xd = Maps{MapIdx}(:,1); 
        Yd = Maps{MapIdx}(:,2);
        
        for ix = 1:nx
            for iy = 1:ny
                x_min = (ix - 2) * cell_size;  x_max = (ix + 1) * cell_size;
                y_min = (iy - 2) * cell_size;  y_max = (iy + 1) * cell_size;
                
                idx = find(Xd >= x_min & Xd < x_max & Yd >= y_min & Yd < y_max);
                count = length(idx);
                
                if count > max_pts_per_nbhd
                    error('局部缺陷密度过高，请调大 max_pts_per_nbhd！');
                end
                
                HashCount(ix, iy, MapIdx) = count; % 注意索引顺序变了
                if count > 0
                    HashX(1:count, ix, iy, MapIdx) = Xd(idx); % p 在第一维
                    HashY(1:count, ix, iy, MapIdx) = Yd(idx);
                end
            end
        end
    end
    
    StaticHashXCell{Rep} = HashX;
    StaticHashYCell{Rep} = HashY;
    StaticHashCountCell{Rep} = HashCount;
    InitPositions(Rep, :) = (1e-6 * rand(1, 2) + 50e-6) * 1e9; 
end

% 将静态表常量化，广播给所有 Worker 节点
ConstHashX = parallel.pool.Constant(StaticHashXCell);
ConstHashY = parallel.pool.Constant(StaticHashYCell);
ConstHashCount = parallel.pool.Constant(StaticHashCountCell);

%% --- [4] 任务解耦与分发 ---
Tasks = [];
for Rep = Repeats
    x0 = InitPositions(Rep, 1);
    y0 = InitPositions(Rep, 2);
    for DistMode = DistributionModes
        for Ts = Ts_list
            for tm_ads = tmads_list
                for vx = Xshiftvelocity_list
                    for vy = Yshiftvelocity_list
                        if DistMode == 1
                            % 幂律分布 (1)：需要遍历 TimeIndex_list 作为幂律指数
                            current_TI_list = TimeIndex_list;
                        else
                            % 指数 (2) & 均匀 (3)：不需要 TI，强制设为 0 作为占位符
                            current_TI_list = [0]; 
                        end                        
                        
                        % 仅对当前分配到的 TI 列表生成任务，追加到 Tasks 矩阵中
                        for TI = current_TI_list
                            Tasks = [Tasks; Ts, tm_ads, TI, vx, vy, DistMode, Rep, x0, y0];
                        end                     
                    end
                end
            end
        end
    end
end

% --- 核心数计算 ---
TotalTasks = size(Tasks, 1); % 获取总任务数 (刚刚好的核心数上限)

% [安全拦截] 检查任务是否为空
if TotalTasks == 0
    error('任务生成失败！总任务数为 0，请检查参数设置！');
end

MaxPhysicalCores = feature('numcores'); % 获取电脑物理核心总数

% 核心算法：min(总任务数, 物理核心数 - 2)
% 使用 max(1, ...) 确保在核心数极少的电脑上至少开启 1 个核心
NumCores = min(TotalTasks, max(1, MaxPhysicalCores - 2));

% [可选] 强制上限：如果内存较小，可以再加一个硬上限，例如 12
% NumCores = min(NumCores, 12); 

fprintf('>>> [%s] 任务总数: %d | 分配核心数: %d \n', ...
        datestr(now, 'HH:MM:SS'), TotalTasks, NumCores);

% --- 动态启动并行池 ---
pool = gcp('nocreate');
if isempty(pool) || pool.NumWorkers ~= NumCores
    if ~isempty(pool), delete(pool); end % 如果当前池核心数不对，先关掉
    fprintf('>>> 正在启动并行池...\n');
    pool = parpool('local', NumCores);
end
% ----------------------------------

setappdata(0, 'taskProg', zeros(1, TotalTasks)); 
setappdata(0, 'lastMsgLen', 0); 
dq = parallel.pool.DataQueue;
afterEach(dq, @(data) update_progress_console(data, TotalTasks, startTime));
futures = parallel.FevalFuture.empty(TotalTasks, 0);

fprintf('>>> [%s] 仿真任务下发完成，开始实时监控...\n', datestr(now, 'HH:MM:SS'));
fprintf('------------------------------------------------------------\n');

% --- 派发任务，传入预计算好的三张哈希表 ---
for i = 1:TotalTasks
    futures(i) = parfeval(pool, @Worker_JumpingTask, 1, i, dq, Tasks(i,:), ...
                          t_total, jf, adR, D, ConstHashX, ConstHashY, ConstHashCount, TimeSeed);
end

%% --- [5] 结果异步回收与智能归档 ---

baseResultDir = 'Simulation_Results';
if ~exist(baseResultDir, 'dir')
    mkdir(baseResultDir);
end

% 1. 创建本次运行的唯一根文件夹 (用于区分不同批次的实验)
runID = datestr(now, 'yyyymmdd_HHMMSS');
mainRunDir = fullfile(baseResultDir, ['Task_' runID]);
if ~exist(mainRunDir, 'dir')
    mkdir(mainRunDir);
end

DistNames = {'PowerLaw', 'Exp', 'Uniform'}; % 分布名称映射

fprintf('>>> 数据归档路径: %s\n', mainRunDir);

for i = 1:TotalTasks
    % 获取完成的任务
    [idx, res] = fetchNext(futures);
    p = Tasks(idx, :);
    
    % 解析物理参数
    curr_Ts = p(1); curr_tmads = p(2); curr_TI = p(3); 
    curr_vx = p(4); curr_vy = p(5); 
    curr_DistMode = p(6); curr_Rep = p(7);
    
    % 数据清洗 (去除 NaN)
    pos = res.pos;
    valid_idx = ~isnan(pos(:,1));
    positionlist = pos(valid_idx, :); 
    
    % 只有有效轨迹才处理
   % 只有有效轨迹才处理
    if size(positionlist, 1) > 2
        DTRACK = 1000; 
        FigN = 0; % 批量运行关闭绘图
        
        % 组装分析参数
        DataTrans_Analysis = [curr_Ts, curr_TI, res.t_r, curr_tmads, res.k, jf, adR, FigN, 0, curr_vx, curr_vy];
        
        try
            cDist = DistNames{curr_DistMode};
            current_k = res.k;
            ratio_k = curr_vx / current_k;
            
            % 建立子文件夹
            subdirName = sprintf('Rep%d_%s_TI%.1f_Tads%.2f_Vx_%g_k_%.3f_ratio_%gk', ...
                   curr_Rep, cDist, curr_TI, curr_tmads, curr_vx, current_k, ratio_k);
            subDirPath = fullfile(mainRunDir, subdirName);
            if ~exist(subDirPath, 'dir')
                mkdir(subDirPath);
            end
            
            filePrefix = sprintf('Rep%d_%s_TI%.1f_Tads%.2f_Vx_%g_k_%.3f_ratio_%gk', ...
                               curr_Rep, cDist, curr_TI, curr_tmads, curr_vx, current_k, ratio_k);
            
            % ========================================================
            % 🚀 智能路由：根据全局开关决定后处理策略
            % ========================================================
            if PerfTestMode
                % [极速模式] 屏蔽子函数，仅保存核心原始数据，避免 I/O 阻塞
                matFilePath = fullfile(subDirPath, [filePrefix, '_Fast_NoPlot.mat']);
                save(matFilePath, 'positionlist', 'p', 'res', '-v7.3');
                
            else
                % [完整模式] 调用后处理引擎，生成图片并保存全套派生矩阵
                % 注意：如果你刚才在 Sub_TrajectoryAnalysis.m 里做了注释，请记得把它们取消注释恢复原状
                [SD, DX, DY, DL, analysis_results] = Sub_TrajectoryAnalysis(positionlist, DTRACK, FigN, curr_Ts, DataTrans_Analysis, subDirPath, filePrefix);
                
                matFilePath = fullfile(subDirPath, [filePrefix, '.mat']);
                save(matFilePath, 'positionlist', 'SD', 'DX', 'DY', 'DL', 'p', 'res', 'analysis_results', '-v7.3');
            end
            % ========================================================
            
            % 控制台轻量输出
            fprintf('\n[OK] Task %d/%d -> %s\n', idx, TotalTasks, subdirName); 
            setappdata(0, 'lastMsgLen', 0);
            
        catch ME
            fprintf('\n[ERROR] Task %d 处理失败: %s\n', idx, ME.message);
            if ~isempty(ME.stack)
                fprintf('  -> 错误发生在: %s (第 %d 行)\n', ME.stack(1).name, ME.stack(1).line);
            end
        end
    else
        fprintf('\n[SKIP] Task %d: 轨迹点数不足，跳过。\n', idx);
    end
end
fprintf('\n'); % 换行

%% --- [6] 实验日志导出与系统扫尾 ---
endTimeStr = datestr(now, 'yyyy-mm-dd HH:MM:SS');
totalDuration = toc(startTime);

% 确保日志目录存在
logDir = 'Experiment_Logs';
if ~exist(logDir, 'dir'), mkdir(logDir); end
logFileName = sprintf('SimLog_%s.txt', runID);
logFilePath = fullfile(logDir, logFileName);

fid = fopen(logFilePath, 'w');
fprintf(fid, '============================================================\n');
fprintf(fid, '单分子跳跃动力学 - 仿真实验报告 \n');
fprintf(fid, '============================================================\n');
fprintf(fid, '【1. 运行系统信息】\n');
fprintf(fid, '  运行 ID                     : %s\n', runID);
fprintf(fid, '  计算核心数                  : %d\n', NumCores);
fprintf(fid, '  开始时间                    : %s\n', startTimeStr);
fprintf(fid, '  结束时间                    : %s\n', endTimeStr);
fprintf(fid, '  总耗时                      : %.2f 分钟\n', totalDuration/60);
fprintf(fid, '  完成任务数                  : %d\n', TotalTasks);
fprintf(fid, '  数据存储位置                : %s\n', fullfile(pwd, mainRunDir));
fprintf(fid, '============================================================\n');
fprintf(fid, '【2. 核心物理常量】\n');
fprintf(fid, '  仿真总时长 (t_total)        : %g s\n', t_total);
fprintf(fid, '  分子跳跃频率 (jf)           : %g Hz\n', jf);
fprintf(fid, '  理论扩散系数 (D)            : %g m^2/s\n', D);
fprintf(fid, '  吸附半径 (adR)              : %g nm\n', adR);
fprintf(fid, '  空间总尺寸 (L_total)        : %g nm\n', L_total);
fprintf(fid, '  缺陷平均间距 (ds)           : %g nm\n', ds);
fprintf(fid, '  跳跃时间步长 (tau)          : %g s\n', tau);
fprintf(fid, '  单步跳跃距离 (k)            : %g nm\n', k);
fprintf(fid, '============================================================\n');
fprintf(fid, '【3. 离散化与扫描参数阵列】\n');
fprintf(fid, '  分布模式 (DistModes)        : %s\n', mat2str(DistributionModes));
fprintf(fid, '  重复实验次数 (Repeats)      : %s\n', mat2str(Repeats));
fprintf(fid, '  相机采样时间 (Ts_list)      : %s s\n', mat2str(Ts_list));
fprintf(fid, '  平均吸附时间 (tmads_list)   : %s s\n', mat2str(tmads_list));
fprintf(fid, '  分布指数 (TI_list)          : %s\n', mat2str(TimeIndex_list));
fprintf(fid, '  X方向漂移 (Vx_list)         : %s nm/s\n', mat2str(Xshiftvelocity_list));
fprintf(fid, '  Y方向漂移 (Vy_list)         : %s nm/s\n', mat2str(Yshiftvelocity_list));
fprintf(fid, '============================================================\n');
fprintf(fid, '【4. 随机种子与空间哈希引擎参数】\n');
fprintf(fid, '  时间种子 (TimeSeed)         : %d\n', TimeSeed);
fprintf(fid, '  基础地图种子 (RNG Seed)     : Rep + TimeSeed\n');
fprintf(fid, '  基础地图大小 (L_block)      : %g nm\n', L_block);
fprintf(fid, '  空间哈希质数X (PrimeX)      : 73856093\n');
fprintf(fid, '  空间哈希质数Y (PrimeY)      : 19349663\n');
fprintf(fid, '  区块调度映射函数            : mod(Ix * PrimeX + Iy * PrimeY + TimeSeed, 4) + 1\n');
fprintf(fid, '============================================================\n');
fclose(fid);

% 清理全局变量并关闭并行池
rmappdata(0, 'taskProg');
rmappdata(0, 'lastMsgLen');
delete(pool); 
end

% =========================================================================
% Worker: 独立运算核心
% =========================================================================
function out = Worker_JumpingTask(taskID, dq, p, t_tot, jf, adR, D, ConstHashX, ConstHashY, ConstHashCount, TimeSeed)
    Ts = p(1); tm_ads = p(2); TI = p(3); vx = p(4); vy = p(5);
    DistMode = p(6); Rep = p(7); x0 = p(8); y0 = p(9);
    
    tau = 1/jf; 
    k = sqrt(2*D*tau) * 1e9; 
    
    % 直接提取当前 Rep 的静态表
    HashX = ConstHashX.Value{Rep}; 
    HashY = ConstHashY.Value{Rep};
    HashCount = ConstHashCount.Value{Rep};
    
    cx = x0; cy = y0; tr = 0; 
    X = []; Y = []; F = [];
    nf = round(t_tot/Ts);
    report_step = max(1, round(nf / 20)); 
    
    for j = 1:nf
        args = [Ts, TI, tr, tm_ads, k, jf, adR, 0, j, vx, vy, DistMode];
        
        % 直接将静态表灌入底层 MEX 引擎
        [xe, ye, Xa, Ya, tr] = Sub_JumpingBetweenEachFrame_mex_mex(cx, cy, HashX, HashY, HashCount, args, TimeSeed);
        
        cx = xe; cy = ye;
        if ~isnan(Xa(1))
            X = [X; Xa']; Y = [Y; Ya']; 
            F = [F; ones(size(Ya'))*j]; 
        end
        if mod(j, report_step) == 0, send(dq, [taskID, j/nf]); end
    end
    send(dq, [taskID, 1.0]); 
    out.pos = [X, Y, F]; out.t_r = tr; out.k = k;
end

% =========================================================================
% 实时进度统计函数 (防屏刷渲染)
% =========================================================================
function update_progress_console(data, total, startTime)
    prog = getappdata(0, 'taskProg');
    prog(data(1)) = data(2);
    setappdata(0, 'taskProg', prog);
    
    len = getappdata(0, 'lastMsgLen');
    
    % --- 增强逻辑：如果 len 为空或被重置为 0，不执行退格 ---
    if isempty(len) || len == 0
        % 打印一个换行符，确保不在上一行残余字符后追加
        fprintf('\n'); 
        len = 0;
    else
        fprintf(repmat('\b', 1, len)); 
    end
    
    delta = sum(prog) / total;
    elap = toc(startTime);
    
    % 核心修复：添加任务完成数的实时状态
    doneCount = sum(prog == 1.0); 
    activeNodes = sum(prog > 0 & prog < 1.0);
    
    if delta > 0
        rem = elap * (1 - delta) / delta;
        etaStr = sprintf('%02d:%02d:%02d', floor(rem/3600), floor(mod(rem,3600)/60), floor(mod(rem,60)));
    else
        etaStr = '--:--:--';
    end
    
    barLen = 20;
    filled = floor(delta * barLen);
    bar = [repmat('>', 1, filled), repmat(' ', 1, barLen - filled)];
    
    % 增加固定宽度的格式化，防止字符抖动导致计算错误
    msg = sprintf('Progress: [%s] %5.1f%% | Done: %d/%d | Active: %d | ETA: %s', ...
                  bar, delta*100, doneCount, total, activeNodes, etaStr);
    
    fprintf('%s', msg);
    setappdata(0, 'lastMsgLen', length(msg));
end
