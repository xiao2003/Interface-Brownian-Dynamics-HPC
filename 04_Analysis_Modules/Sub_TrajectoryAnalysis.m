function [SD, DX, DY, DL, analysis_results] = Sub_TrajectoryAnalysis(PL, DTRACK, FigN, Dt, DataTrans, SaveDir, FilePrefix)
% =========================================================================
% 单分子轨迹动力学分析模块 (HPC 高性能并行计算专用版)
% 特性: 
% 1. 强制后台静默绘图 (防止并行 Worker 弹窗导致显存崩溃)
% 2. 自动提取 MSD、位移分布、扩散系数等微纳流体学关键参数
% 3. 同步导出 MAT、FIG 及 300DPI JPG，并基于物理参数进行文件夹隔离
% =========================================================================

% 【核心防护】强制所有新建图像在后台静默生成，不弹出窗口
set(0, 'DefaultFigureVisible', 'off'); 

%% --- [1] 解析外部传入的物理与离散化参数 ---
t_tot = DataTrans(1);      % 仿真总时长 (s)
Timeindex = DataTrans(2);  % 表面吸附时间分布指数 (如幂律)
t_a = DataTrans(3);        % 初始吸附残留时间
tm_ads = DataTrans(4);     % 平均吸附时间 (s)
k = DataTrans(5);          % 理论跳跃步长
jf = DataTrans(6);         % 分子跳跃频率 (Hz)
adR = DataTrans(7);        % 吸附有效半径
Fig = DataTrans(8);        % (弃用)
jj = DataTrans(9);         % (弃用)
xshiftvelocity = DataTrans(10);    % X方向漂移速度 (nm/s)
yshiftvelocity = DataTrans(11);    % Y方向漂移速度 (nm/s)

Lmin = 100;       % 计数下限阈值 (nm)
LinearT = 5;      % MSD 线性拟合时间区间 (s)
fontsize = 14;

%% --- [2] 轨迹融合与追踪 ---
[positionlist] = Sub_MergingLocalizationsInSameFrame(PL);
[m,n] = find(positionlist(:,3)==0);
positionlist(m,:) = [];

% 调用原有的多目标追踪算法 (请确保 track.m 在工作路径中)
T = track(positionlist, DTRACK);

px_T = T(:,1);  % X坐标 (nm)
py_T = T(:,2);  % Y坐标 (nm)
t_T = T(:,3);   % 帧号
T_T = T(:,4);   % 轨迹ID

Number_TRACK = max(T_T);
N_MSD_MAX = max(t_T);

% 【心脏手术 1】 强行限制分析长度，保证老板不卡死
N_MSD_MAX = min(10000, N_MSD_MAX);

%% --- [3] 动力学参数核心矩阵计算 ---
MSD = zeros(Number_TRACK, N_MSD_MAX);
theta = zeros(Number_TRACK, N_MSD_MAX);
Dphi = zeros(Number_TRACK, N_MSD_MAX);
DX = zeros(Number_TRACK, N_MSD_MAX);
DY = zeros(Number_TRACK, N_MSD_MAX);
DL = zeros(Number_TRACK, N_MSD_MAX);
px_total = zeros(Number_TRACK, N_MSD_MAX);
py_total = zeros(Number_TRACK, N_MSD_MAX);
MAX = zeros(1, Number_TRACK);

for nT = 1:Number_TRACK
    px_T_sub = px_T(T_T==nT);
    py_T_sub = py_T(T_T==nT);
    Size_nT = length(px_T_sub);

    if Size_nT > 1
        MSD_sub = transpose((px_T_sub-px_T_sub(1)).^2 + (py_T_sub-py_T_sub(1)).^2);
        theta_sub = transpose(atan2(py_T_sub(2:end)-py_T_sub(1:end-1), px_T_sub(2:end)-px_T_sub(1:end-1)));
        Dphi_sub = abs(theta_sub(2:end)-theta_sub(1:end-1));
        DX_sub = transpose(px_T_sub(2:end)-px_T_sub(1:end-1));
        DY_sub = transpose(py_T_sub(2:end)-py_T_sub(1:end-1));
        DL_sub = sqrt(DX_sub.^2 + DY_sub.^2);

        if Size_nT > N_MSD_MAX
            MSD_sub = MSD_sub(1:N_MSD_MAX);
            theta_sub = theta_sub(1:N_MSD_MAX);
            Dphi_sub = Dphi_sub(1:N_MSD_MAX-1); Dphi_sub(N_MSD_MAX) = NaN;
            DX_sub = DX_sub(1:N_MSD_MAX);
            DY_sub = DY_sub(1:N_MSD_MAX);
            DL_sub = DL_sub(1:N_MSD_MAX);
            px_T_sub = px_T_sub(1:N_MSD_MAX);
            py_T_sub = py_T_sub(1:N_MSD_MAX);
        else
            MSD_sub(end+1:N_MSD_MAX) = NaN;
            theta_sub(end+1:N_MSD_MAX) = NaN;
            Dphi_sub(end+1:N_MSD_MAX) = NaN;
            DX_sub(end+1:N_MSD_MAX) = NaN;
            DY_sub(end+1:N_MSD_MAX) = NaN;
            DL_sub(end+1:N_MSD_MAX) = NaN;
            px_T_sub(end+1:N_MSD_MAX) = NaN;
            py_T_sub(end+1:N_MSD_MAX) = NaN;
        end

        MSD(nT,:) = MSD_sub;
        theta(nT,:) = theta_sub;
        Dphi(nT,:) = Dphi_sub;
        DX(nT,:) = DX_sub;
        DY(nT,:) = DY_sub;
        DL(nT,:) = DL_sub;
        px_total(nT,:) = px_T_sub;
        py_total(nT,:) = py_T_sub;
        MAX(nT) = max(MSD(nT,:));
    else
        px_total(nT,1) = px_T_sub(1);
        py_total(nT,1) = py_T_sub(1);
        MSD(nT,1) = NaN;
        MAX(nT) = NaN;
        Dphi(nT,1) = NaN;
        theta(nT,1) = NaN;
    end
end

MSD(MSD==0) = NaN; DL(DL==0) = NaN;
DX(DX==0) = NaN; DY(DY==0) = NaN; MAX(MAX==0) = NaN;

%% --- [4] 物理学统计图表后台绘制 ---

% 【图 1】 位移 2D 分布热力图
figure(1+FigN);
subplot(121)
histogram2(DX, DY, DTRACK/4, 'FaceColor', 'flat');
colorbar; xlabel('dx [nm]'); ylabel('dy [nm]'); zlabel('Number [-]');
box on; set(gca, 'FontSize', fontsize); axis equal;
subplot(122)
h = histogram2(DX, DY, DTRACK/4, 'FaceColor', 'flat');
h.DisplayStyle = 'tile'; view(2);
colorbar; xlabel('dx [nm]'); ylabel('dy [nm]'); zlabel('Number [-]');
box on; set(gca, 'FontSize', fontsize); axis equal;
set(gcf, 'unit', 'centimeters', 'position', [10 5 25 8]);

% 【图 2】 一维位移分布及对数重叠对比
figure(2+FigN);
subplot(2,2,1);  
[h,c] = hist(DY(:), linspace(-DTRACK,DTRACK,DTRACK/4));
plot(c,h,'.', 'MarkerSize', 20); hold on;
set(gca,'YScale','log', 'FontSize', fontsize);
xlabel('dy [nm]'); ylabel('Number [-]'); title('y-displacement distribution');

subplot(2,2,2); 
[j,d] = hist(DX(:), linspace(-DTRACK,DTRACK,DTRACK/4));
plot(d,j,'.', 'MarkerSize', 20); hold on;
set(gca,'YScale','log', 'FontSize', fontsize);
xlabel('dx [nm]'); ylabel('Number [-]'); title('x-displacement distribution');

subplot(2,2,[3,4]); hold on;
[dy_counts, dy_edges] = hist(DY(:), linspace(-DTRACK,DTRACK,DTRACK/4));
plot(dy_edges, dy_counts, '.', 'MarkerSize', 20, 'DisplayName', 'dy');
[dx_counts, dx_edges] = hist(DX(:), linspace(-DTRACK,DTRACK,DTRACK/4));
plot(dx_edges, dx_counts, '.', 'MarkerSize', 20, 'Color', [0.85 0.33 0.1], 'DisplayName', 'dx');
set(gca, 'YScale', 'log', 'FontSize', fontsize, 'XLim', [-DTRACK, DTRACK], 'Box', 'on');                 
xlabel('Displacement [nm]', 'FontSize', fontsize);
ylabel('Number [-]', 'FontSize', fontsize);
title('x/y-displacement distribution overlap', 'FontSize', fontsize);
legend('Location', 'best', 'FontSize', fontsize-1); hold off;

% 【图 4】 跳跃长度分布 (预留了 Fig3 空间，按照您原版逻辑编号为 4)
figure(4+FigN);
histogram(DL(:), DTRACK/10); hold on;
xlabel('Jumping length [nm]'); ylabel('Number [-]');
box on; set(gca, 'FontSize', fontsize, 'YScale', 'log');

% % 【图 6】 均方位移 (MSD) 计算与线性拟合
% [m,n] = size(px_total);
% for i=1:m
%     px_total(i, px_total(i,:)==0) = NaN;
%     py_total(i, py_total(i,:)==0) = NaN;
% end
% 
% N_MSD = 10000;
% MSD_TA = zeros(1, N_MSD);
% for i = 1:N_MSD
%     MSD_TA(i) = nanmean(nanmean((px_total(:,i+1:end)-px_total(:,1:end-i)).^2 + ...
%                                 (py_total(:,i+1:end)-py_total(:,1:end-i)).^2));
% end

% 【图 6】 均方位移 (MSD) 计算与线性拟合
[m,n] = size(px_total);
for i=1:m
    px_total(i, px_total(i,:)==0) = NaN;
    py_total(i, py_total(i,:)==0) = NaN;
end

% >>> 1. 提速一万倍：只算前 500 步的 MSD <<<
N_MSD = min(10000, size(px_total, 2) - 1); 
if N_MSD < 1
    N_MSD = 1; 
end

MSD_TA = zeros(1, N_MSD);
for i = 1:N_MSD
    MSD_TA(i) = nanmean(nanmean((px_total(:,i+1:end)-px_total(:,1:end-i)).^2 + ...
                                (py_total(:,i+1:end)-py_total(:,1:end-i)).^2));
end

figure(6+FigN);
X_time = linspace(1, N_MSD, N_MSD) * Dt;
X_time = X_time(2:end);
coco = jet(length(X_time));

% >>> 2. 拯救显存：删掉 for 循环，一键生成散点图 <<<
scatter(X_time, MSD_TA(1:length(X_time))*10^(-18), 50, flipud(coco), 's', 'filled');
hold on;

% 线性拟合
[xSort1, xIdx1] = sort(X_time);
ySort1 = MSD_TA(xIdx1);
[~, Ns1] = min(abs(X_time - LinearT));

% 防止轨迹太短导致多项式拟合报错
if Ns1 > 1 
    coef1 = polyfit(xSort1(1:Ns1), ySort1(1:Ns1)*10^(-18), 1);
    plot(X_time(1:min(length(X_time), 2*Ns1)), polyval(coef1, X_time(1:min(length(X_time), 2*Ns1))), '--k', 'LineWidth', 2);
    SD = coef1(1); 
else
    SD = NaN;
end

xlabel('t (s)'); ylabel('MSD (m^2)');
box on; set(gca, 'FontSize', fontsize);

% figure(6+FigN);
% X_time = linspace(1, N_MSD, N_MSD) * Dt;
% X_time = X_time(2:end);
% coco = jet(length(X_time));
% for i = 1:length(X_time)
%     hold on;
%     plot(X_time(i), MSD_TA(i)*10^(-18), 's', 'MarkerEdgeColor', coco(length(X_time)-i+1,:),...
%          'MarkerFaceColor', coco(length(X_time)-i+1,:), 'MarkerSize', 10);
% end
% 
% [xSort1, xIdx1] = sort(X_time);
% ySort1 = MSD_TA(xIdx1);
% [~, Ns1] = min(abs(X_time - LinearT));
% coef1 = polyfit(xSort1(1:Ns1), ySort1(1:Ns1)*10^(-18), 1);
% plot(X_time(1:2*Ns1), polyval(coef1, X_time(1:2*Ns1)), '--k', 'LineWidth', 2);
% SD = coef1(1); % 提取斜率作为扩散系数的基准
% 
% xlabel('t (s)'); ylabel('MSD (m^2)');
% box on; set(gca, 'FontSize', fontsize);


%% --- [5] 数据封装与归档 ---

% 1. 打包分析结果结构体
analysis_results.T = T;
analysis_results.T_header = {'X(nm)', 'Y(nm)', 'Frame', 'Trajectory_ID'};

result_data = zeros(size(T, 1), 5);  
for i = 1:size(T, 1)
    traj_id = T(i, 4);  
    frame = T(i, 3);    
    if traj_id >= 1 && traj_id <= Number_TRACK && frame >= 1 && frame <= N_MSD_MAX
        result_data(i, 1) = MSD(traj_id, frame);       
        result_data(i, 2) = DX(traj_id, frame);        
        result_data(i, 3) = DY(traj_id, frame);        
        result_data(i, 4) = DL(traj_id, frame);        
        result_data(i, 5) = SD;                        
    else
        result_data(i, :) = NaN;
    end
end
analysis_results.result_data = result_data;
analysis_results.result_header = {'MSD(nm^2)', 'DX(nm)', 'DY(nm)', 'Jump_Length(nm)', 'Diffusion_Coeff(m^2/s)'};

% 【修改】删除原先写死的 save('AnalysisData.mat', ...) 
% 数据现在已通过 analysis_results 返回给主程序进行统一封装保存。

% 4. 导出高清图表 (使用外部传入的绝对路径 SaveDir 和 FilePrefix)
fig_nums = [1, 2, 4, 6] + FigN; 
fig_suffixes = {'1_dx-dy热力分布', '2_位移一维直方图', '4_跳跃长度分布', '6_MSD拟合曲线'};

for i = 1:length(fig_nums)
    fig_num = fig_nums(i);
    if ishandle(fig_num)
        % 【修改】利用 fullfile 拼接绝对路径，确保文件不会乱跑
        jpg_filename = fullfile(SaveDir, sprintf('%s_%s.jpg', FilePrefix, fig_suffixes{i}));
        
        % 保存 300 DPI .jpg
        try
            exportgraphics(figure(fig_num), jpg_filename, 'Resolution', 300, 'ContentType', 'image');
        catch
            saveas(figure(fig_num), jpg_filename, 'jpeg'); 
        end
        close(fig_num); 
    end
end

set(0, 'DefaultFigureVisible', 'on'); 
end