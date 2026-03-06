% Sub_JumpingAtMolecularFreq()
% Last modified 03/12/2025
clear; clc; close all;

cleanup_parallel('cpu')

turn = 1;% 0 = 自动关机  1 = 不自动关机
claen = 0;% 0 =自动清理  1 = 不自动清理

Date = date;
NN = 1;                     % 轨迹数量
t_total = 1000;             % 每条轨迹总时间
jf = 10^10;                 % 跳跃频率(Hz)
Ts = [0.02];                % 相机采样时间
AdRR = 1;
adR = 1 * AdRR;             % 吸附半径(nm)
tmads = [0.2 0.2 0.2 0.3 0.3 0.3 0.5 0.5 0.5 0.7 0.7 0.7 0.9 0.9 0.9 1.0 1.0 1.0];  % 平均吸附时间(s)
ds = [20];                  % 缺陷间距(nm)
Xshiftvelocity = [0];       % X方向漂移速度(nm/s)
Yshiftvelocity = zeros(size(Xshiftvelocity));  % Y方向漂移速度(nm/s)
DistributionMode = 1;       % 分布模式

% 根据分布模式设置时间参数
switch DistributionMode
    case 1
        TimeIndex = 1000;  % 幂律分布参数
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
CORE_NUM = M * Mean * TL * DS;

% ----------------------并行模式设置----------------------
parallel_mode = 'cpu'; 
% -------------------------------------------------------
% 
% Flag = zeros(Mean*N*DS*TL);

% 主循环结构（按并行模式处理）
if strcmp(parallel_mode, 'cpu')
    % CPU并行：使用parfor处理最外层循环，内层循环保持串行
    for ti = 1:N
        for dss = 1:DS
            for tl = 1:TL
                init_parallel(parallel_mode,CORE_NUM);  % 初始化并行环境
                    parfor midx = 1:Mean  % CPU多线程并行核心 - 使用不同的变量名避免冲突
                       cpu_process_trajectory(midx, ti, dss, tl, ...
                            TimeIndex, tmads(midx), Ts, ds, t_total, jf, D, ...
                            L_total, Xshiftvelocity, Yshiftvelocity, ...
                            DistributionMode, Mnt, adR)
                    end
                % 清理并行环境
                if clean == 0
                    cleanup_parallel(parallel_mode);
                end
             end
         end
     end
end


% for flag = 1 : M
%     if Flag(flag) == 1
%         printf('第%d进程成功结束\n',flag)
%     end
% end    

% 系统关机（按需启用）
if turn == 0
    system('shutdown -s');
end

% ----------------------并行环境初始化/清理函数----------------------
function init_parallel(mode,core_num)
    switch mode
        case 'cpu'
            % 初始化CPU并行池
            if isempty(gcp('nocreate'))
                parpool(core_num);  % 根据CPU核心数自动分配
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
                delete(gcp('nocreate'));
                fprintf('CPU并行池已关闭\n');
            end
        case 'gpu'
            % 清理GPU内存
            fprintf('GPU内存已清理\n');
    end
end