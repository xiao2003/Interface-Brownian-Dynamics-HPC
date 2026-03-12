function JumpingAtMolecularFreq()
% =========================================================================
% 单分子表面跳跃动力学仿真 (终极整合版)
% 核心优势: 
% 1. 彻底消除 Worker 节点的随机数开销与主客节点间的海量通信拥堵
% 2. 引入动态持续性进度条与 ETA 监控
% 3. 精确调用 Coder 编译的底层 C/C++ 引擎 (mex_mex)
% 4. [新增] 全自动结果提取、NaN清理、轨迹分析 (Sub_TrajectoryAnalysis)
% 5. [新增] 基于物理参数的动态 .mat 文件命名与分类归档
% =========================================================================

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

NumCores = min(10, feature('numcores')); % 预留系统核心避免系统卡顿

fprintf('>>> [%s] 并行池启动中 (分配核心数: %d)...\n', datestr(now, 'HH:MM:SS'), NumCores);
pool = parpool('local', NumCores);       

%% --- [2] 实验参数配置 (Experimental Configuration) ---
startTime = tic;
startTimeStr = datestr(now, 'yyyy-mm-dd HH:MM:SS');

% 核心物理常量
t_total = 1000;             % 仿真总时长 (s)
jf = 10^8;                 % 分子跳跃频率 (Hz)
D = 10^(-10);                % 理论扩散系数 (m^2/s)
adR = 1.0;                  % 吸附半径 (nm)
L_total = 100 * 1e3;        % 空间总尺寸 100um -> 100,000 nm
ds = 40;                    % 缺陷平均间距 (nm)

tau = 1/jf;
k = sqrt(2*D*tau) * 1e9; 

% 离散化与时空尺度扫描阵列
DistributionModes = [1,2,3];       % 1: 幂律分布, 2: 指数分布, 3: 均匀分布 (先测一种避免任务过多)
Repeats = 1:1;                 % 重复实验次数 (亦作为独立地图的样本数)

Ts_list = [0.02];              % 相机采样时间 (s)
tmads_list = [0.05];           % 平均吸附时间 (s)
TimeIndex_list = [-2.5,2.5];       % 幂律分布指数 (TI) 
Xshiftvelocity_list = [0.0002, 0.0008, 0.002, 0.008]*k;% X方向漂移速度 (nm/s) - 0为纯扩散对照组
Yshiftvelocity_list = [0];     % Y方向漂移速度 (nm/s)

%% --- [3] 预生成缺陷地图阵列 (核心内存优化与空间哈希准备) ---
fprintf('>>> [%s] 正在预生成基础缺陷区块与旋转缺陷区块...\n', datestr(now, 'HH:MM:SS'));

L_block = 10000; % 基础区块的边长 (nm)
Ndefect_block = round(L_block/ds); % 单个区块对应的理论缺陷维度

% 为每次重复实验 (Rep) 生成一套独立的 4 张地图字典
MapCell = cell(1, max(Repeats)); 
InitPositions = zeros(max(Repeats), 2);

for Rep = Repeats
    rng(Rep, 'twister'); % 以 Rep 作为随机数种子，确保严格对照
    
    % 1. 生成基础地图 Map1
    % 将缺陷限制在 [adR, L_block - adR] 范围内，造出"无缺陷护城河"
    valid_L = L_block - 2 * adR; 
    Map1 = rand(Ndefect_block^2, 2) * valid_L + adR; 
    
    % 2. 旋转生成另外三张地图 (坐标变换)
    Map2 = [Map1(:, 2), L_block - Map1(:, 1)];             % 转90度
    Map3 = [L_block - Map1(:, 1), L_block - Map1(:, 2)];   % 转180度
    Map4 = [L_block - Map1(:, 2), Map1(:, 1)];             % 转270度
    
    % 3. 打包当前 Rep 的四张地图字典
    MapCell{Rep} = {Map1, Map2, Map3, Map4}; 
    
    % 初始坐标仍然保留在全局坐标系中（如 50000 nm 附近）
    InitPositions(Rep, :) = (1e-6 * rand(1, 2) + 50e-6) * 1e9; 
end

% 此时传入并行的 ConstMaps 数据量被缩减了数百倍！
ConstMaps = parallel.pool.Constant(MapCell);

%% --- [4] 任务解耦与分发 ---
Tasks = [];
for Rep = Repeats
    x0 = InitPositions(Rep, 1);
    y0 = InitPositions(Rep, 2);
    for DistMode = DistributionModes
        for Ts = Ts_list
            for tm_ads = tmads_list
                for TI = TimeIndex_list
                    for vx = Xshiftvelocity_list
                        for vy = Yshiftvelocity_list
                            Tasks = [Tasks; Ts, tm_ads, TI, vx, vy, DistMode, Rep, x0, y0];
                        end
                    end
                end
            end
        end
    end
end
TotalTasks = size(Tasks, 1);

setappdata(0, 'taskProg', zeros(1, TotalTasks)); 
setappdata(0, 'lastMsgLen', 0); 

dq = parallel.pool.DataQueue;
afterEach(dq, @(data) update_progress_console(data, TotalTasks, startTime));
futures = parallel.FevalFuture.empty(TotalTasks, 0);

fprintf('>>> [%s] 仿真任务下发完成，开始实时监控...\n', datestr(now, 'HH:MM:SS'));
fprintf('------------------------------------------------------------\n');

for i = 1:TotalTasks
    futures(i) = parfeval(pool, @Worker_JumpingTask, 1, i, dq, Tasks(i,:), ...
                          t_total, jf, adR, D, ConstMaps);
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
    if size(positionlist, 1) > 2
        DTRACK = 1000; 
        FigN = 0; % 批量运行关闭绘图
        
        % 组装分析参数
        DataTrans_Analysis = [curr_Ts, curr_TI, res.t_r, curr_tmads, res.k, jf, adR, FigN, 0, curr_vx, curr_vy];
        
        try
            cDist = DistNames{curr_DistMode};
            
            % 建立子文件夹
            subdirName = sprintf('Rep%d_%s_TI%.1f_Tads%.2f_Vx_%g', ...
                   curr_Rep, cDist, curr_TI, curr_tmads, curr_vx);
            subDirPath = fullfile(mainRunDir, subdirName);
            
            if ~exist(subDirPath, 'dir')
                mkdir(subDirPath);
            end
            
            % 构建唯一的文件名前缀 (包含 Rep 防止覆盖)
            filePrefix = sprintf('Rep%d_%s_TI%.1f_Tads%.2f_Vx%.0f', ...
                               curr_Rep, cDist, curr_TI, curr_tmads, curr_vx);
            
            % --- 【修改】彻底移除 cd 逻辑，将路径和前缀传给子函数 ---
            % 执行轨迹分析，直接让子函数生成图片到指定路径
            [SD, DX, DY, DL, analysis_results] = Sub_TrajectoryAnalysis(positionlist, DTRACK, FigN, curr_Ts, DataTrans_Analysis, subDirPath, filePrefix);
            
            % 保存核心数据矩阵 (使用 fullfile 指定绝对路径)
            matFilePath = fullfile(subDirPath, [filePrefix, '.mat']);
            save(matFilePath, 'positionlist', 'SD', 'DX', 'DY', 'DL', 'p', 'res', 'analysis_results', '-v7.3');
            
            % 控制台轻量输出
            fprintf('\r[OK] Task %d/%d -> %s', idx, TotalTasks, subdirName);
            
        catch ME
            % 如果出错，打印详细报错信息与行号，方便定位
            fprintf('\n[ERROR] Task %d 处理失败: %s\n', idx, ME.message);
            if ~isempty(ME.stack)
                fprintf('  -> 错误发生在: %s (第 %d 行)\n', ME.stack(1).name, ME.stack(1).line);
            end
        end
    else
        % --- 之前漏掉的 else 和 end 补在这里 ---
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
fprintf(fid, '单分子跳跃动力学 - 仿真实验报告\n');
fprintf(fid, '============================================================\n');
fprintf(fid, '运行 ID: %s\n', runID);
fprintf(fid, '计算核心数：%d\n', NumCores);
fprintf(fid, '开始时间：%s\n', startTimeStr);
fprintf(fid, '结束时间：%s\n', endTimeStr);
fprintf(fid, '总耗时：%.2f 分钟\n', totalDuration/60);
fprintf(fid, '完成任务数：%d\n', TotalTasks);
fprintf(fid, '数据存储位置：%s\n', fullfile(pwd, mainRunDir));
fprintf(fid, '============================================================\n');
fprintf(fid, '扫描参数:\n');
fprintf(fid, '  Vx_list: [%s]\n', mat2str(Xshiftvelocity_list));
fprintf(fid, '  Tads_list: [%s]\n', mat2str(tmads_list));
fclose(fid);

fprintf('\n------------------------------------------------------------\n');
fprintf('>>> 全部任务完成！\n');
fprintf('>>> [日志] %s\n', logFilePath);
fprintf('>>> [数据] %s\n', mainRunDir);
fprintf('------------------------------------------------------------\n');

% 清理全局变量并关闭并行池
rmappdata(0, 'taskProg');
rmappdata(0, 'lastMsgLen');
delete(pool); 
end

% =========================================================================
% Worker: 独立运算核心 (升级为 3x3 空间哈希动态拼接)
% =========================================================================

function out = Worker_JumpingTask(taskID, dq, p, t_tot, jf, adR, D, ConstMaps)
    Ts = p(1); tm_ads = p(2); TI = p(3); vx = p(4); vy = p(5);
    DistMode = p(6); Rep = p(7); x0 = p(8); y0 = p(9);
    
    tau = 1/jf; 
    k = sqrt(2*D*tau) * 1e9; 
    
    % 获取当前 Rep 对应的 4 张旋转护城河地图
    Maps = ConstMaps.Value{Rep}; 
    L_block = 10000; % 必须与 Step 1 生成地图时的 L_block 保持一致
    
    cx = x0; cy = y0; tr = 0; 
    X = []; Y = []; F = [];
    nf = round(t_tot/Ts);
    report_step = max(1, round(nf / 40)); 
    
    Th_u = 5000; cx_c = -1e10; cy_c = -1e10; XY_l = zeros(0, 2);
    
    for j = 1:nf
        % 当分子移动超过阈值，重新组装周边的 3x3 九宫格缺陷地图
        if abs(cx - cx_c) > Th_u || abs(cy - cy_c) > Th_u
            Ix_center = floor(cx / L_block);
            Iy_center = floor(cy / L_block);
            
            XY_l = [];
            % 遍历当前区块周围的 9 个网格
            for dix = -1:1
                for diy = -1:1
                    Ix = Ix_center + dix;
                    Iy = Iy_center + diy;
                    
                    % 核心：空间哈希函数，永远为同一个网格分配相同的地形
                    MapIdx = mod(Ix * 73856093 + Iy * 19349663, 4) + 1;
                    BlockDefects = Maps{MapIdx};
                    
                    % 将局部坐标转换为真实的全局坐标，无缝拼合
                    BlockDefects(:,1) = BlockDefects(:,1) + Ix * L_block;
                    BlockDefects(:,2) = BlockDefects(:,2) + Iy * L_block;
                    
                    XY_l = [XY_l; BlockDefects]; % 汇总入局部地图
                end
            end
            cx_c = cx; cy_c = cy;
        end
        
        args = [Ts, TI, tr, tm_ads, k, jf, adR, 0, j, vx, vy, DistMode];
        % 此时传给底层 MEX 的 XY_l 是一个极其安全的 30000x30000 区域
        [xe, ye, Xa, Ya, tr] = Sub_JumpingBetweenEachFrame_mex_mex(cx, cy, XY_l, args);
        
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
    delta = sum(prog) / total;
    elap = toc(startTime);
    
    if delta >= 0.01
        rem = elap * (1 - delta) / delta;
        h = floor(rem/3600); m = floor(mod(rem,3600)/60); s = floor(mod(rem,60));
        eta = sprintf('%02d:%02d:%02d', h, m, s);
    else
        eta = 'Estimating...'; 
    end
    
    c_num = sum(prog >= 0.999);      
    a_num = sum(prog > 0 & prog < 1);
    
    fprintf(repmat('\b', 1, len));
    bar_w = 20; 
    f_w = floor(delta * bar_w);
    bar = [repmat('>', 1, f_w), repmat(' ', 1, bar_w - f_w)];
    str = sprintf('Progress: [%s] %5.1f%% | Done: %d/%d | Active Nodes: %d | ETA: %s', ...
                  bar, delta*100, c_num, total, a_num, eta);
    fprintf('%s', str);
    
    setappdata(0, 'lastMsgLen', length(str));
end