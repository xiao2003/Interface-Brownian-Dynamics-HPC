function [SD,DX,DY,DL] = Sub_TrajectoryAnalysis(PL,DTRACK,FigN,Dt, DataTrans, BatchRoot)
%UNTITLED 此处显示有关此函数的摘要
% DTRACK: the maximum tracking length: nm

t_tot = DataTrans(1);      % time interval between each frame or the total simulation time here (Sampling time of camera)
Timeindex = DataTrans(2);  % Time parameters of adsorption time
t_a = DataTrans(3);        % Subsequent adsorption time due to the adsorption event from the last frame
tm_ads = DataTrans(4);     % Mean adsoption time before the next relocation: s
k = DataTrans(5);          % Molecular jumping distance at a given diffusion coefficient
jf = DataTrans(6);         % Jumping frequency
adR = DataTrans(7);        % Adsorption radius
Fig = DataTrans(8);        % Figure Number
jj = DataTrans(9);         % The jjth frame
xshiftvelocity = DataTrans(10);    % Shift Velocity in x axis : nm/s
yshiftvelocity = DataTrans(11);    % Shift Velocity in y axis : nm/s
DistributionMode = DataTrans(12);
RepeatID = DataTrans(13);
if nargin < 6 || isempty(BatchRoot)
    BatchRoot = pwd;
end
FN ={};         % Saving file name
Lmin = 100;     % jumping length above which the jumping is counted: nm
LinearT = 5;  % Linear fitting to find MSD: s
fontsize = 14;

% Spatial Offset Stacking: 若输入含第4列 Repeat 标签，则在分析模块内执行 1e9 nm 偏移
if size(PL,2) >= 4
    rep_tags = PL(:,4);
    unique_reps = unique(rep_tags(:))';
    for ridx = 1:length(unique_reps)
        r = unique_reps(ridx);
        shift_nm = (ridx - 1) * 1e9;
        row_idx = (rep_tags == r);
        PL(row_idx,1) = PL(row_idx,1) + shift_nm;
        PL(row_idx,2) = PL(row_idx,2) + shift_nm;
    end
    PL = PL(:,1:3);
end

[positionlist] = Sub_MergingLocalizationsInSameFrame(PL);
[m,n] = find(positionlist(:,3)==0);
positionlist(m,:)=[];

T = track(positionlist,DTRACK);
% T = track(positionlist(1:258000,:),DTRACK);
% T = track(PL,DTRACK);

%%
px_T = T(:,1);  % in nm
py_T = T(:,2);  % in nm
t_T = T(:,3);   % in frame
T_T = T(:,4);   % index of tracking point

Number_TRACK = max(T_T);
N_MSD_MAX = max(t_T);

%%

%%

MSD = zeros(Number_TRACK,N_MSD_MAX);
theta = zeros(Number_TRACK,N_MSD_MAX);
Dphi = zeros(Number_TRACK,N_MSD_MAX);
DX = zeros(Number_TRACK,N_MSD_MAX);
DY = zeros(Number_TRACK,N_MSD_MAX);
DL = zeros(Number_TRACK,N_MSD_MAX);
DLX = zeros(Number_TRACK,N_MSD_MAX);
DLY = zeros(Number_TRACK,N_MSD_MAX);
px_total = zeros(Number_TRACK,N_MSD_MAX);
py_total = zeros(Number_TRACK,N_MSD_MAX);

for nT = (1:Number_TRACK)
    Size(nT) = length(px_T(T_T==nT));

    % if mod(nT,100)==0
    %     strcat(num2str(nT/100),'/',num2str(Number_TRACK/100));
    % end

    px_T_sub = px_T(T_T==nT);
    py_T_sub = py_T(T_T==nT);
    %nT
    if Size(nT)>1
        Xmean(nT) = mean(px_T_sub);
        Ymean(nT) = mean(py_T_sub);
        %
        MSD_sub = transpose((px_T_sub-px_T_sub(1)).^2+(py_T_sub-py_T_sub(1)).^2);
        theta_sub = transpose(atan2(py_T_sub(2:end)-py_T_sub(1:end-1),px_T_sub(2:end)-px_T_sub(1:end-1)));
        Dphi_sub = abs(theta_sub(2:end)-theta_sub(1:end-1));
        DX_sub = transpose(px_T_sub(2:end)-px_T_sub(1:end-1));
        DY_sub = transpose(py_T_sub(2:end)-py_T_sub(1:end-1));
        DL_sub = sqrt(DX_sub.^2+DY_sub.^2);

        if Size(nT)>N_MSD_MAX
            MSD_sub=MSD_sub(1:N_MSD_MAX);
            theta_sub=theta_sub(1:N_MSD_MAX);
            Dphi_sub=Dphi_sub(1:N_MSD_MAX-1);
            Dphi_sub(N_MSD_MAX)=NaN;
            DX_sub=DX_sub(1:N_MSD_MAX);
            DY_sub=DY_sub(1:N_MSD_MAX);
            DL_sub=DL_sub(1:N_MSD_MAX);
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

        MSD(nT,1)=NaN;
        MAX(nT) = NaN;
        Dphi(nT,1) = NaN;
        theta(nT,1)= NaN;
    end


end
%
MSD(MSD==0)=NaN;
DL(DL==0)=NaN;
DX(DX==0)=NaN;
DY(DY==0)=NaN;
MAX(MAX==0)=NaN;

% 防串轨诊断：若出现接近空间偏移量(1e9 nm)的异常步长，输出告警
DL_flat = DL(:);
DL_flat = DL_flat(~isnan(DL_flat));
if ~isempty(DL_flat)
    suspicious = sum(DL_flat > 1e8);
    if suspicious > 0
        fprintf('[WARN] 检测到 %d 个超大跳跃(>1e8 nm)，请检查重复轨迹拼接是否发生跨轨迹误连。\n', suspicious);
    end
end

%% Displacement distributions in x and y
figure(1+FigN);
subplot(121)
h = histogram2(DX,DY,DTRACK/4,'FaceColor','flat');
colorbar
xlabel('dx [nm]'); ylabel('dy [nm]'),zlabel('Number [-]')
box on
set(gca,'FontSize',fontsize);
axis equal
subplot(122)
h = histogram2(DX,DY,DTRACK/4,'FaceColor','flat');
h.DisplayStyle = 'tile';
view(2)
colorbar
xlabel('dx [nm]'); ylabel('dy [nm]'),zlabel('Number [-]')
box on
set(gca,'FontSize',fontsize);
axis equal
set(gcf, 'unit', 'centimeters', 'position', [10 5 25 8]);

figure(2+FigN);
title('Displacement distribution');
subplot(2,2,1);  % 2行2列布局：第1行第1列
[h,c] = hist(DY(:),linspace(-DTRACK,DTRACK,DTRACK/4));
hold on
plot(c,h,'.', 'MarkerSize', 20);
set(gca,'YScale','log');
xlabel('dy [nm]');
ylabel('Number [-]');
title('y-displacement distribution');
set(gca,'FontSize',fontsize);

subplot(2,2,2);  % 2行2列布局：第1行第2列
[j,d] = hist(DX(:), linspace(-DTRACK,DTRACK,DTRACK/4));
hold on
plot(d,j,'.', 'MarkerSize', 20);
set(gca,'YScale','log');
xlabel('dx [nm]');
ylabel('Number [-]');
% ylim([1 100000]);
title('x-displacement distribution');
set(gca,'FontSize',fontsize);

% ---------------------- 第三个子图：dx和dy重叠对比（修复布局错误） ----------------------
subplot(2,2,[3,4]);  % 2行2列布局：第2行第1-2列（占用整行）
hold on;

% 复用dy的分布数据和样式（与子图1完全一致）
[dy_counts, dy_edges] = hist(DY(:), linspace(-DTRACK,DTRACK,DTRACK/4));
plot(dy_edges, dy_counts, '.', 'MarkerSize', 20, 'DisplayName', 'dy');

% 复用dx的分布数据和样式（与子图2完全一致，仅加颜色区分）
[dx_counts, dx_edges] = hist(DX(:), linspace(-DTRACK,DTRACK,DTRACK/4));
plot(dx_edges, dx_counts, '.', 'MarkerSize', 20, 'Color', [0.85 0.33 0.1], 'DisplayName', 'dx');

% 完全沿用前两个子图的坐标轴/格式设置
set(gca, ...
    'YScale', 'log', ...          % 对数Y轴（与子图1/2一致）
    'FontSize', fontsize, ...     % 字体大小统一
    'XLim', [-DTRACK, DTRACK], ...% x轴范围与前两个图一致
    'Box', 'on');                 % 边框样式统一

% 标签与标题（保持格式一致）
xlabel('Displacement [nm]', 'FontSize', fontsize);
ylabel('Number [-]', 'FontSize', fontsize);
title('x/y-displacement distribution overlap', 'FontSize', fontsize);

% 图例（区分dx/dy，不遮挡分布）
legend('Location', 'best', 'FontSize', fontsize-1);

hold off;

%
% figure(3+FigN)
% hold on
% plot(d,j/max(j),'.', 'MarkerSize', 20)
% [dx,xn] = Sub_GaussianFit(d,j/max(j),Gcutoff);
% plot(dx,xn,'LineWidth',2)
% plot(c,h/max(h),'.', 'MarkerSize', 20)
% [dy,yn] = Sub_GaussianFit(c,h/max(h),Gcutoff);
% plot(dy,yn,'LineWidth',2)
% xlabel('dx, dy [nm]');
% ylabel('Number [-]');
% legend('x distrib.','x Gaussian fit','y distrib.','y Gaussian fit');
% set(gca,'YScale','log');
% axis([min(c) max(c) 0.0001 1])
% box on
% set(gca,'FontSize',fontsize);

%% Jump event

figure(4+FigN)
hold on

% [h0,c0] = hist(DL(~isnan(DL)),DTRACK/10);
% [h1,c1] = hist(DL(:),DTRACK/10);
% plot(c1,h1,'o','LineWidth',2,'Color',LColor,...
%                        'MarkerEdgeColor',LColor,...
%                        'MarkerFaceColor',LColor,...
%                        'MarkerSize',5)
h1 = histogram(DL(:),DTRACK/10);
xlabel('Jumping length [nm]')
ylabel('Number [-]')
box on
set(gca,'FontSize',fontsize);
set(gca,'YScale','log');
f1=figure(4+FigN);
%
% [nbr_jumps,t_ads] = Sub_JumpingAnalysis(DL,N_MSD_MAX,Lmin);
% figure(5+FigN)
% subplot(121)
% hold on
% h2 = histogram(nbr_jumps,N_MSD_MAX);
% xlabel('Jumping events from each trajectory [-]')
% ylabel('Number [-]')
% box on
% set(gca,'FontSize',fontsize);
% set(gca,'YScale','log');
% title(strcat('\Delta L > ',num2str(Lmin),'nm'))
% subplot(122)
% hold on
% h3 = histogram(t_ads,N_MSD_MAX);
% xlabel('Jumping time from each trajectory [frames]')
% ylabel('Number [-]')
% box on
% set(gca,'FontSize',fontsize);
% set(gca,'YScale','log');
% title(strcat('\Delta L > ',num2str(Lmin),'nm'))
%
% f2=figure(5+FigN);      % adjusting the figure size
% f2.Position(3)=2*f1.Position(3);
%% Mean Square Displacement
[m,n]=size(px_total);
for i=1:m
    px_total(i,px_total(i,:)==0) = NaN;
    py_total(i,py_total(i,:)==0) = NaN;
end

N_MSD =  10000;

for i=(1:N_MSD)
    MSD_TA(i) = nanmean(nanmean((px_total(:,i+1:end)-px_total(:,1:end-i)).^2+(py_total(:,i+1:end)-py_total(:,1:end-i)).^2));
end


figure(6+FigN);
X_time = linspace(1,N_MSD,N_MSD)*Dt;
X_time = X_time(2:end);

coco = jet(length(X_time));
for i=1:length(X_time)
    hold on;
    plot(X_time(i),MSD_TA(i)*10^(-18),'s','MarkerEdgeColor',coco(length(X_time)-i+1,:),...
                       'MarkerFaceColor',coco(length(X_time)-i+1,:),...
                       'MarkerSize',10);
end




%%  Linear fit to MSD_TA

disp('Linear fit to MSD_TA')
[xSort1, xIdx1] = sort(X_time);
ySort1 = MSD_TA(xIdx1);
[Ps1,Ns1] = min(abs(X_time-LinearT));
coef1 = polyfit(xSort1(1:Ns1),ySort1(1:Ns1)*10^(-18),1);
plot(X_time(1:2*Ns1),polyval(coef1,X_time(1:2*Ns1)),'--k','LineWidth',2)
SD = coef1(1);

xlabel('t (s)');
ylabel('MSD (m^2)');
box on
set(gca,'FontSize',fontsize);


%
% %% Distribution of trajectories
%
% figure(5+FigN)
% hold on
% [h,c] = hist(Size,max(Size));
% plot(c,h,'-'); %plot the number of trajectories of each sizes
% xlabel('Trajectory size [frame]')
% ylabel('Number [-]')
% set(gca,'XScale','log');
% set(gca,'YScale','log');
% box on
% set(gca,'FontSize',fontsize);

coco = flag(6);
%
% for i=1:10
%     disp('###################Please give a proper cut-off length for the jumping:     #################')
%     DTRACKK=input('The maximum jumping length considered (nm), input 0 if it is already well defined:  ')
%     if DTRACKK==0
%         break
%     end
%     % if i~=1
%     %     close(FigN+1,FigN+2,FigN+3,FigN+4,FigN+5)
%     % end
%     DataTrans=[Gcutoff,DTRACKK,Dt,LinearT,FigN,fontsize,N_MSD_MAX];
%     [DXX, DYY, DLL, px_total,py_total] = Sub_TrackingLengthTuned(positionlist,DataTrans,coco(i,:));
%
%     figure(3+FigN)
%     set(gca,'YScale','log');
%     axis([min(c) max(c) 0.0001 1])
%     box on
%     set(gca,'FontSize',fontsize);
% end
%
%
%
% disp('###################Please give a proper cut-off length for the linear regime to find the diffusion coeffi.:     #################')
% LinearT=input('T cut-off for the linear regime (s):  ')
%
% clf(FigN+6)
% [Slope] = Sub_FindingMobilityLinearFitting(px_total,py_total,N_MSD_MAX,Dt,LinearT,FigN+6)
%


sprintf('Total frame processed: %.1f',t_T(end)-t_T(1)+1)
sprintf('Dt between each frame: %.1f ms',Dt*1000)
sprintf('Total localizations: %.1f',length(px_T))
sprintf('Total trajectories: %.1f',max(T_T))

%
% px_T = T(:,1);  % in nm
% py_T = T(:,2);  % in nm
% t_T = T(:,3);   % in frame
% T_T = T(:,4);   % index of tracking point



% save(FN)

%
% S = input('Continue? Press any number to continue: ')
%
% close all
%

% 1. 准备分析结果数据结构
% 创建结构体存储所有数据
analysis_results = struct();

% 存储T矩阵原始数据
analysis_results.T = T;
analysis_results.T_header = {'X(nm)', 'Y(nm)', 'Frame', 'Trajectory_ID'};

% 准备按行匹配的分析结果
result_data = zeros(size(T, 1), 5);  % 5列分析结果：MSD、DX、DY、Jump_Length、Diffusion_Coeff

for i = 1:size(T, 1)
    traj_id = T(i, 4);  % 当前行的轨迹ID
    frame = T(i, 3);    % 当前行的帧号

    % 填充分析结果（无效数据用NaN）
    if traj_id >= 1 && traj_id <= Number_TRACK && frame >= 1 && frame <= N_MSD_MAX
        result_data(i, 1) = MSD(traj_id, frame);       % MSD
        result_data(i, 2) = DX(traj_id, frame);        % X方向位移
        result_data(i, 3) = DY(traj_id, frame);        % Y方向位移
        result_data(i, 4) = DL(traj_id, frame);        % 跳跃长度
        result_data(i, 5) = SD;                        % 扩散系数
    else
        result_data(i, :) = NaN;
    end
end

% 存储分析结果数据及标题
analysis_results.result_data = result_data;
analysis_results.result_header = {'MSD(nm^2)', 'DX(nm)', 'DY(nm)', 'Jump_Length(nm)', 'Diffusion_Coeff(m^2/s)'};

% 2. 生成带北京时间的文件名（与原Excel同名，仅修改后缀）
beijing_time = datetime('now', 'TimeZone', 'Asia/Shanghai');
time_str = datestr(beijing_time, 'yyyy-mm-dd-HH-MM-SS');
switch DistributionMode
    case 1
        mat_filename = sprintf('幂律分布_Rep%d_%s模拟数据_模拟采样时长%.2f_模拟参数%.2f_平均吸附时间%.2fs_x方向上滑移速度%.2fnm_s_y方向上滑移速度%.2fnm_s.mat', ...
            RepeatID, time_str, t_tot, Timeindex, tm_ads, xshiftvelocity, yshiftvelocity);
    case 2
        mat_filename = sprintf('指数分布_Rep%d_%s模拟数据_模拟采样时长%.2f_平均吸附时间%.2fs_x方向上滑移速度%.2fnm_s_y方向上滑移速度%.2fnm_s.mat', ...
            RepeatID, time_str, t_tot,tm_ads, xshiftvelocity, yshiftvelocity);
    case 3
        mat_filename = sprintf('均匀分布_Rep%d_%s模拟数据_模拟采样时长%.2f_平均吸附时间%.2fs_x方向上滑移速度%.2fnm_s_y方向上滑移速度%.2fnm_s.mat', ...
            RepeatID, time_str, t_tot, tm_ads, xshiftvelocity, yshiftvelocity);
end
% 添加：创建与MAT文件同名的文件夹（去除.mat后缀）
folder_name = fullfile(BatchRoot, mat_filename(1:end-4));  % 提取MAT文件名作为文件夹名
if ~exist(folder_name, 'dir')         % 检查文件夹是否存在
    mkdir(folder_name);               % 不存在则创建
end

% 3. 保存为MAT文件（路径指向新文件夹）
mat_filepath = fullfile(folder_name, mat_filename);  % 拼接文件夹路径
save(mat_filepath, 'analysis_results');
fprintf('分析结果已导出至：%s\n', mat_filepath);

%% 保存为 MATLAB 原生 .fig 格式 + 同名 JPG 格式（同目录）
% 提取图片文件名前缀（去除.mat后缀）
img_prefix = mat_filename(1:end-4);

% 获取当前所有由本函数生成的figure句柄（基于FigN偏移，共6个图表）
fig_nums = (1+FigN) : (6+FigN);

% 为每个图表添加描述性后缀（与fig_nums顺序严格对应）
fig_suffixes = {
    'dx-dy分布', ...      % 1+FigN: dx-dy二维分布
    'xy方向位移直方图', ... % 2+FigN: x/y方向位移分布
    '轨迹可视化', ...      % 3+FigN: 补充实际功能（根据你的图表修改）
    '跳跃长度分布', ...     % 4+FigN: 跳跃长度直方图
    '吸附时间分布', ...     % 5+FigN: 补充实际功能（根据你的图表修改）
    '均方位移MSD'          % 6+FigN: MSD曲线与拟合
};

% 遍历所有图表，同时保存.fig和jpg至新文件夹
for i = 1:length(fig_nums)
    fig_num = fig_nums(i);
    if ishandle(fig_num)  % 检查图表是否存在（避免报错）
        % 1. 生成 .fig 格式文件名（前缀+图表描述+.fig后缀）
        fig_filename = sprintf('%s_%s.fig',fig_suffixes{i},img_prefix);
        fig_filepath = fullfile(folder_name, fig_filename);  % 路径指向新文件夹

        % 2. 生成同名 .jpg 格式文件名（仅替换后缀）
        jpg_filename = strrep(fig_filename, '.fig', '.jpg');
        jpg_filepath = fullfile(folder_name, jpg_filename);

        % 3. 保存为 MATLAB 原生 .fig 格式
        h_fig = figure(fig_num); % 获取真实的图窗对象句柄
        savefig(h_fig, fig_filepath); % 传入句柄进行保存
        fprintf('图表已保存为 .fig 格式：%s\n', fig_filepath);
        % 4. 保存为高分辨率 JPG 格式（同目录、同名）
        % 切换到目标figure，设置保存分辨率（r300=300DPI，可调整为150/600）
        figure(fig_num);
        print(fig_num, '-djpeg', '-r300', jpg_filepath); % -djpeg指定jpg格式，-r300设置分辨率
        fprintf('图表已保存为 JPG 格式：%s\n', jpg_filepath);
    else
        fprintf('警告：图表编号 %d 不存在，跳过保存\n', fig_num);
    end
end
fprintf('正常退出');
end
