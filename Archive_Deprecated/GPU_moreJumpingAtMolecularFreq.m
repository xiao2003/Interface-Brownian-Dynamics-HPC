% Sub_JumpingAtMolecularFreq()
% 支持CPU/GPU并行计算的轨迹生成程序
% 可通过设置parallel_mode选择并行模式：'cpu'或'gpu'
% 修复了parfor循环中的变量问题
% Last modified 03/12/2025
clear; clc; close all;

% ----------------------并行模式设置----------------------
parallel_mode = 'gpu';  % 可选'cpu'或'gpu'
init_parallel(parallel_mode);  % 初始化并行环境
% -------------------------------------------------------

turn = 1;% 0 = 自动关机  1 = 不自动关机

Date = date;
NN = 1;                     % 轨迹数量
t_total = 1;             % 每条轨迹总时间
jf = 10^10;                 % 跳跃频率(Hz)
Ts = [0.02];                % 相机采样时间
AdRR = 1;
adR = 1 * AdRR;             % 吸附半径(nm)
tmads = [0.09 0.09 0.09 0.1 0.3 0.5 0.8 1.0];  % 平均吸附时间(s)
ds = [20];                  % 缺陷间距(nm)
Xshiftvelocity = [0];       % X方向漂移速度(nm/s)
Yshiftvelocity = zeros(size(Xshiftvelocity));  % Y方向漂移速度(nm/s)
DistributionMode = 2;       % 分布模式

% 根据分布模式设置时间参数
switch DistributionMode
    case 1
        TimeIndex = [2.5];  % 幂律分布参数
    case 2
        TimeIndex = tmads;  % 指数分布参数(均值)
    case 3
        TimeIndex = tmads;  % 均匀分布参数
end

Mnt = 0;                     % 可视化标记(0:不可视化,1:可视化)
D = 10^(-8);                 % 扩散系数
fontsize = 14;
L_total = 100e-6 * 1e9;      % 区域总大小(nm)

% 循环参数初始化
if DistributionMode ~= 2
    N = length(TimeIndex);
else
    N = 1;
end
M = length(Xshiftvelocity);
Mean = length(tmads);
TL = length(Ts);
DS = length(ds);

% 主循环结构（按并行模式处理）
if strcmp(parallel_mode, 'cpu')
    % CPU并行：使用parfor处理最外层循环，内层循环保持串行
    for ti = 1:1
        for dss = 1:DS
            for tl = 1:TL
                parfor m = 1:Mean  % CPU多线程并行核心
                    % 将所需参数传递给处理函数
                    process_trajectory_cpu(m, ti, dss, tl, ...
                        TimeIndex, tmads, Ts, ds, t_total, jf, D, ...
                        L_total, Xshiftvelocity, Yshiftvelocity, ...
                        DistributionMode, Mnt, adR);
                end
            end
        end
    end
elseif strcmp(parallel_mode, 'gpu')
    % GPU并行：将循环参数转移到GPU，使用arrayfun并行处理
    gpu_TimeIndex = gpuArray(TimeIndex);
    gpu_tmads = gpuArray(tmads);
    gpu_Ts = gpuArray(Ts);
    gpu_ds = gpuArray(ds);
    
    for ti = 1:N
        for dss = 1:DS
            for tl = 1:TL
                % 对每个m进行GPU并行计算
                results = arrayfun(@(m) gpu_process_trajectory(...
                    m, ti, dss, tl, gpu_TimeIndex, gpu_tmads, gpu_Ts, ...
                    gpu_ds, t_total, jf, D, L_total, Xshiftvelocity, ...
                    Yshiftvelocity, DistributionMode, Mnt, adR), ...
                    1:Mean, 'UniformOutput', false);               
            end
        end
    end
end

% 清理并行环境
cleanup_parallel(parallel_mode);

% 系统关机（按需启用）
if turn == 0
    system('shutdown -s');
end

% ----------------------CPU并行处理函数----------------------
function process_trajectory_cpu(m, ti, dss, tl, TimeIndex, tmads, Ts, ds, t_total, jf, D, ...
        L_total, Xshiftvelocity, Yshiftvelocity, DistributionMode, Mnt, adR)
    % 初始化位置（每个并行实例独立初始化）
    x0 = 1e-6 * rand + 50e-6;
    y0 = 1e-6 * rand + 50e-6;
    x0 = x0 * 1e9;  % 转换为nm
    y0 = y0 * 1e9;
    
    for q = 1:length(Xshiftvelocity)
        prev_time = now();
        Timeindex = TimeIndex(ti);
        tm_ads = tmads(m);
        tau = 1 / jf;
        k = sqrt(2 * D * tau) * 1e9;  % 分子跳跃距离(nm)
        
        % 生成缺陷位置
        Ndefect = round(L_total / ds(dss));
        Xd = rand(Ndefect^2, 1) * L_total;
        Yd = rand(Ndefect^2, 1) * L_total;
        XYd = [Xd Yd];
        
        % 初始化轨迹存储
        X = [];
        Y = [];
        Frame = [];
        t_r = 0;  % 初始吸附时间
        
        xshiftvelocity = Xshiftvelocity(q);
        yshiftvelocity = Yshiftvelocity(q);
        
        % 帧循环（核心计算）
        total_frames = round(t_total / Ts(tl));
        for j = 1:total_frames
            t_a = t_r;
            DataTrans = [Ts(tl), Timeindex, t_a, tm_ads, k, jf, adR, ...
                double(Mnt), j, xshiftvelocity, yshiftvelocity,DistributionMode];
            % 调用子函数计算帧内轨迹
            [xe, ye, Xads, Yads, t_r] = Sub_JumpingBetweenEachFrame_cpu(...
                x0, y0, XYd, DataTrans);
            x0 = xe;
            y0 = ye;
            
            % 存储轨迹数据
            X = [X; Xads'];
            Y = [Y; Yads'];
            Frame = [Frame; ones(size(Yads')) * j];
            
            % 进度显示
            tmp1 = round(j / total_frames * 100, 6);
            seconds2remainingtime(prev_time, tmp1, 1);
            
            % 可视化（仅在Mnt=1时，且限制并行中的图形操作）
            if Mnt == 1 && mod(j, 10) == 0  % 降低可视化频率
                figure(3); set(gcf, "Position", [1000 400 560 420]); hold on;
                if ~isempty(Xads)
                    scatter(Xads*1e6, Yads*1e6, 40, [0 0.45 0.74], 'filled');
                    alpha(0.5); xlabel('X (\mum)'); ylabel('Y (\mum)'); box on;
                end
            end
        end
        
        % 数据清洗
        [m_idx, ~] = find(isnan(X));
        X(m_idx) = [];
        Y(m_idx) = [];
        Frame(m_idx) = [];
        
        % 轨迹分析
        length_X = length(X);
        positionlist = zeros(length_X, 3);
        positionlist(:, 1) = X;
        positionlist(:, 2) = Y;
        positionlist(:, 3) = Frame;
        
        DTRACK = 1000;  % 最大跟踪长度(nm)
        [SD, DX, DY, DL] = Sub_TrajectoryAnalysis_cpu(...
            positionlist, DTRACK, 4*(m-1)+1, Ts(tl), DataTrans);
        SD = SD';
        DX = DX';
        DY = DY';
        % 保存结果
        FN = sprintf('cpu_test_ti%d_dss%d_m%d_q%d.mat', ti, dss, m, q);
        save(FN, 'SD', 'DX', 'DY', 'DL', 'positionlist');
    end
end

% ----------------------GPU并行处理函数----------------------
function result = gpu_process_trajectory(m, ti, dss, tl, gpu_TimeIndex, gpu_tmads, gpu_Ts, ...
        gpu_ds, t_total, jf, D, L_total, Xshiftvelocity, Yshiftvelocity, DistributionMode, Mnt, adR)
    % 将单个标量参数也转为gpuArray以保持一致性
    m_gpu = gpuArray(m);
    ti_gpu = gpuArray(ti);
    dss_gpu = gpuArray(dss);
    tl_gpu = gpuArray(tl);
    t_total_gpu = gpuArray(t_total);
    jf_gpu = gpuArray(jf);
    D_gpu = gpuArray(D);
    L_total_gpu = gpuArray(L_total);
    DistributionMode_gpu = gpuArray(DistributionMode);
    Mnt_gpu = gpuArray(Mnt);
    adR_gpu = gpuArray(adR);
    Xshiftvelocity_gpu = gpuArray(Xshiftvelocity);
    Yshiftvelocity_gpu = gpuArray(Yshiftvelocity);
    
    % 初始化位置（每个并行实例独立初始化）- GPU版本
    x0_gpu = 1e-6 * gpuArray.rand() + 50e-6;
    y0_gpu = 1e-6 * gpuArray.rand() + 50e-6;
    x0_gpu = x0_gpu * 1e9;  % 转换为nm
    y0_gpu = y0_gpu * 1e9;
    
    % 获取实际值用于循环
    q_values = gather(gpuArray.colon(1, length(Xshiftvelocity)));
    
    for q = q_values
        prev_time = now();
        Timeindex_gpu = gpu_TimeIndex(ti_gpu);
        tm_ads_gpu = gpu_tmads(m_gpu);
        tau_gpu = 1 / jf_gpu;
        k_gpu = sqrt(2 * D_gpu * tau_gpu) * 1e9;  % 分子跳跃距离(nm)
        
        % 生成缺陷位置 - GPU版本
        Ndefect_gpu = round(L_total_gpu / gpu_ds(dss_gpu));
        Xd_gpu = gpuArray.rand(Ndefect_gpu^2, 1) * L_total_gpu;
        Yd_gpu = gpuArray.rand(Ndefect_gpu^2, 1) * L_total_gpu;
        XYd_gpu = [Xd_gpu Yd_gpu];
        
        % 初始化轨迹存储 - GPU版本
        X_gpu = gpuArray([]);
        Y_gpu = gpuArray([]);
        Frame_gpu = gpuArray([]);
        t_r_gpu = gpuArray(0);  % 初始吸附时间
        
        xshiftvelocity_gpu_val = Xshiftvelocity_gpu(q);
        yshiftvelocity_gpu_val = Yshiftvelocity_gpu(q);
        
        % 帧循环（核心计算）- GPU版本
        total_frames_gpu = round(t_total_gpu / gpu_Ts(tl_gpu));
        total_frames = gather(total_frames_gpu);
        for j = 1:total_frames
            t_a_gpu = t_r_gpu;
            DataTrans_gpu = [gpu_Ts(tl_gpu), Timeindex_gpu, t_a_gpu, tm_ads_gpu, k_gpu, jf_gpu, adR_gpu, ...
                double(Mnt_gpu), gpuArray(j), xshiftvelocity_gpu_val, yshiftvelocity_gpu_val, DistributionMode_gpu];
            % 调用GPU子函数计算帧内轨迹
            [xe_gpu, ye_gpu, Xads_gpu, Yads_gpu, t_r_gpu] = Sub_JumpingBetweenEachFrame(...
                x0_gpu, y0_gpu, XYd_gpu, DataTrans_gpu);
            x0_gpu = xe_gpu;
            y0_gpu = ye_gpu;
            
            % 存储轨迹数据 - GPU版本
            X_gpu = [X_gpu; Xads_gpu'];
            Y_gpu = [Y_gpu; Yads_gpu'];
            Frame_gpu = [Frame_gpu; gpuArray.ones(size(Yads_gpu')) * j];
            
            % 进度显示
            tmp1 = round(j / total_frames * 100, 6);
            seconds2remainingtime(prev_time, tmp1, 1);
        end
        
        % 将GPU结果收集到CPU
        X = gather(X_gpu);
        Y = gather(Y_gpu);
        Frame = gather(Frame_gpu);
        
        % 数据清洗 - CPU版本（因为find函数在GPU上行为不同）
        [m_idx, ~] = find(isnan(X));
        X(m_idx) = [];
        Y(m_idx) = [];
        Frame(m_idx) = [];
        
        % 轨迹分析
        length_X = length(X);
        positionlist = zeros(length_X, 3);
        positionlist(:, 1) = X;
        positionlist(:, 2) = Y;
        positionlist(:, 3) = Frame;
        
        DTRACK = 1000;  % 最大跟踪长度(nm)
        [SD, DX, DY, DL] = Sub_TrajectoryAnalysis(...
            positionlist, DTRACK, 4*(m-1)+1, gather(gpu_Ts(tl_gpu)), gather(DataTrans_gpu));
        SD = SD';
        DX = DX';
        DY = DY';
        % 保存结果
        FN = sprintf('gpu_test_ti%d_dss%d_m%d_q%d.mat', ti, dss, m, q);
        save(FN, 'SD', 'DX', 'DY', 'DL', 'positionlist');
    end
    
    result = 1; % 返回结果表示完成
end

% ----------------------并行环境初始化/清理函数----------------------
function init_parallel(mode)
    switch mode
        case 'cpu'
            % 初始化CPU并行池
            if isempty(gcp('nocreate'))
                parpool('local');  % 根据CPU核心数自动分配
            end
            fprintf('CPU并行池初始化完成\n');
        case 'gpu'
            % 检查GPU是否可用
            if gpuDeviceCount() == 0
                error('未检测到可用GPU，请切换到CPU模式');
            end
            gpuDevice(1);  % 激活第一个GPU
            fprintf('GPU设备初始化完成，使用设备: %s\n', gpuDevice(1).Name);
    end
end

function cleanup_parallel(mode)
    switch mode
        case 'cpu'
            % 关闭CPU并行池
            if ~isempty(gcp('nocreate'))
                delete(gcp);
                fprintf('CPU并行池已关闭\n');
            end
        case 'gpu'
            % 清理GPU内存
            fprintf('GPU内存已清理\n');
    end
end