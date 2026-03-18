function Actual_AdsorptionTime_Filtered()
% =========================================================================
% 功能描述：整合分析单分子微观与宏观动力学，生成综合全景图表。
% 排版架构：外部 2x2，D图内嵌 2x4。采用极紧凑布局实现等比例坐标系的完美对齐。
% =========================================================================
clc; clear; close all;
%% --- 1. 实验参数与环境配置 ---
ControlVars     = {'Tads0.0032_', 'adR1_', 'DS100_', 'ratio_0k', 'jf1e+08'}; 
InvestigateVars = {'PowerLaw_TI-2.5', 'PowerLaw_TI2.5', 'Exp', 'Uniform'};
Colors = [0.00, 0.45, 0.74; 0.85, 0.33, 0.10; 0.93, 0.69, 0.13; 0.49, 0.18, 0.56];
NumBins       = 80;    
Ts_Target     = 0.02;  
MaxLagFrames  = 50;    
FontSize_Axis = 13;    
TimeWindow_Zoom = [0, inf];  
%% --- 2. 数据目录定位与检索 ---
DataDir = fullfile(pwd, 'Simulation_Results');
Target_Dir = fullfile(DataDir, 'analysis');
if ~exist(Target_Dir, 'dir')
    taskDirs = dir(fullfile(DataDir, 'Task_*'));
    [~, idx] = max([taskDirs.datenum]);
    Target_Dir = fullfile(DataDir, taskDirs(idx).name);
    fprintf('[INFO] 重定向至最新数据集目录: %s\n', taskDirs(idx).name);
end
all_items = dir(Target_Dir);
subfolders = all_items([all_items.isdir] & ~ismember({all_items.name}, {'.','..'}));
%% --- 3. 初始化数据存储阵列 ---
T_ads_All    = cell(1, length(InvestigateVars)); 
MSD_Sum      = zeros(MaxLagFrames, length(InvestigateVars));
MSD_Count    = zeros(MaxLagFrames, length(InvestigateVars));
SampleTraj   = cell(1, length(InvestigateVars)); 
SampleTraj_T = cell(1, length(InvestigateVars)); 
fprintf('\n================ 微观吸附时间统计报告 ================\n');
fprintf('%-20s | %-12s | %-12s | %-12s | %-12s\n', 'Distribution', 'Target Mean', 'Actual Mean', 'Actual Max', 'Sample Size');
fprintf('----------------------------------------------------------------------------------\n');
%% --- 4. 核心数据遍历与特征提取 ---
for iVar = 1:length(InvestigateVars)
    current_var = InvestigateVars{iVar};
    match_mask = true(1, length(subfolders));
    for c = 1:length(ControlVars), match_mask = match_mask & contains({subfolders.name}, ControlVars{c}); end
    match_mask = match_mask & contains({subfolders.name}, current_var);
    matching_folders = subfolders(match_mask);
    if isempty(matching_folders), continue; end
    
    target_tmads  = NaN;
    for f = 1:length(matching_folders)
        folder_path = fullfile(Target_Dir, matching_folders(f).name);
        mat_files = dir(fullfile(folder_path, '*.mat'));
        for m = 1:length(mat_files)
            try
                data = load(fullfile(folder_path, mat_files(m).name), 'positionlist', 't_ads_history', 'p');
                if isfield(data,'p') && length(data.p) >= 2, target_tmads = data.p(2); end
                
                if isfield(data,'t_ads_history') && ~isempty(data.t_ads_history)
                    t_ads = data.t_ads_history(:);
                    T_ads_All{iVar} = [T_ads_All{iVar}; t_ads(~isnan(t_ads) & t_ads > 0)]; 
                end
                
                if ~isfield(data,'positionlist') || size(data.positionlist,1) < 10, continue; end
                pos = data.positionlist; 
                
                frames = round(pos(:,3)); min_f = min(frames); f_idx = frames - min_f + 1;
                sum_x = accumarray(f_idx, pos(:,1)); sum_y = accumarray(f_idx, pos(:,2)); count_f = accumarray(f_idx, 1);
                valid = count_f > 0; x_cam = sum_x(valid) ./ count_f(valid); y_cam = sum_y(valid) ./ count_f(valid);
                f_cam = find(valid) + min_f - 1;
                
                if isempty(SampleTraj{iVar}) && length(x_cam) > 10
                    SampleTraj{iVar} = [x_cam, y_cam]; SampleTraj_T{iVar} = f_cam * Ts_Target; 
                end
                
                for lag = 1:MaxLagFrames
                    dx = x_cam(1+lag:end) - x_cam(1:end-lag); dy = y_cam(1+lag:end) - y_cam(1:end-lag); df = f_cam(1+lag:end) - f_cam(1:end-lag);
                    valid_steps = (df == lag);
                    if any(valid_steps)
                        MSD_Sum(lag, iVar) = MSD_Sum(lag, iVar) + sum((dx(valid_steps).^2 + dy(valid_steps).^2) * 1e-6); 
                        MSD_Count(lag, iVar) = MSD_Count(lag, iVar) + sum(valid_steps);
                    end
                end
            catch
                continue;
            end
        end
    end
    if ~isempty(T_ads_All{iVar})
        fprintf('%-20s | %-12.4f | %-12.4e | %-12.4f | %-12d\n', strrep(current_var,'_',' '), target_tmads, mean(T_ads_All{iVar}), max(T_ads_All{iVar}), length(T_ads_All{iVar}));
    end
end
fprintf('----------------------------------------------------------------------------------\n\n');
%% =====================================================================
% 绘制综合动力学全景图 (1600x850 宽屏适配 2x4 内网格)
% =====================================================================
figure('Name', 'Comprehensive Single Molecule Dynamics', 'Position', [50, 50, 1600, 850]);
t_outer = tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
% ---------------------------------------------------------------------
% 子图 (a): 微观吸附时间分布 PDF 
% ---------------------------------------------------------------------
nexttile(t_outer, 1); hold on; box on;
set(gca, 'XScale', 'log', 'YScale', 'log', 'FontSize', FontSize_Axis, 'LineWidth', 1.5, 'TickDir', 'in');
plot_handles1 = []; plot_labels1 = {};
for iVar = 1:length(InvestigateVars)
    t_data = T_ads_All{iVar};
    if isempty(t_data), continue; end
    min_t = max(1e-8, min(t_data)); max_t = max(t_data);
    if max_t > min_t * 1.01 
        edges = logspace(log10(min_t), log10(max_t), NumBins);
        counts = histcounts(t_data, edges); centers = sqrt(edges(1:end-1).*edges(2:end));
        widths = diff(edges); pdf = counts ./ (sum(counts).*widths); pidx = pdf > 0;
        h = scatter(centers(pidx), pdf(pidx), 30, Colors(iVar,:), 'filled', 'MarkerFaceAlpha', 0.7, 'MarkerEdgeColor', 'none');
        plot_handles1 = [plot_handles1, h]; plot_labels1{end+1} = strrep(InvestigateVars{iVar},'_',' '); 
    end
end
ref_x = [1e-3, 1e1]; ref_y = [1e1, 1e1 * (ref_x(2)/ref_x(1))^(-2.5)];
h_ref = plot(ref_x, ref_y, 'k--', 'LineWidth', 2);
plot_handles1 = [plot_handles1, h_ref]; plot_labels1{end+1} = 'Theory \sim \tau^{-2.5}';
legend(plot_handles1, plot_labels1, 'Location', 'southwest', 'FontSize', 10, 'Box', 'off');
xlabel('Micro-Adsorption Time \tau_{ads} (s)', 'FontWeight', 'bold'); ylabel('PDF G(\tau_{ads})', 'FontWeight', 'bold');
title('(a) Adsorption Time Distribution', 'FontSize', 14); xlim([1e-5, 1e2]); ylim([1e-8, 1e5]);
% ---------------------------------------------------------------------
% 子图 (b): 宏观均方位移 MSD 
% ---------------------------------------------------------------------
nexttile(t_outer, 2); hold on; box on;
set(gca, 'XScale', 'log', 'YScale', 'log', 'FontSize', FontSize_Axis, 'LineWidth', 1.5, 'TickDir', 'in');
t_lags = (1:MaxLagFrames)' * Ts_Target;
plot_handles2 = []; plot_labels2 = {};
for iVar = 1:length(InvestigateVars)
    if sum(MSD_Count(:, iVar)) > 0
        msd_val = MSD_Sum(:, iVar) ./ MSD_Count(:, iVar);
        p_fit = polyfit(log10(t_lags), log10(msd_val), 1); alpha_val = p_fit(1); 
        h = plot(t_lags, msd_val, '-o', 'Color', Colors(iVar,:), 'MarkerFaceColor', Colors(iVar,:), 'LineWidth', 2, 'MarkerSize', 5);
        plot_handles2 = [plot_handles2, h]; plot_labels2{end+1} = sprintf('%s (\\alpha=%.2f)', strrep(InvestigateVars{iVar},'_',' '), alpha_val); 
        if iVar == 1, ref_base_x = t_lags(1); ref_base_y = msd_val(1); end
    end
end
if exist('ref_base_x', 'var')
    ref_y_msd = ref_base_y * (t_lags / ref_base_x).^1;
    h_ref_msd = plot(t_lags, ref_y_msd, 'k--', 'LineWidth', 2);
    plot_handles2 = [plot_handles2, h_ref_msd]; plot_labels2{end+1} = 'Theory (\alpha=1.00)';
    legend(plot_handles2, plot_labels2, 'Location', 'northwest', 'FontSize', 10, 'Box', 'off');
end
xlabel('Time Lag \Delta t (s)', 'FontWeight', 'bold'); ylabel('MSD (\mu m^2)', 'FontWeight', 'bold');
title('(b) Mean Square Displacement', 'FontSize', 14);
% ---------------------------------------------------------------------
% 子图 (c): 时间域位移演化 
% ---------------------------------------------------------------------
nexttile(t_outer, 3); 
D_val = 1e-10; jf_val = 1e8; 
k_um = (sqrt(2 * D_val * (1/jf_val)) * 1e9) * 1e-3; 
N_jumps = round(Ts_Target * jf_val); 
N_frames_pure = round(1000 / Ts_Target);
pure_t = (1:N_frames_pure)' * Ts_Target;
rng(12345); 
pure_x = cumsum(sqrt(N_jumps) * k_um * randn(N_frames_pure, 1));
valid_idx_p = (pure_t >= TimeWindow_Zoom(1)) & (pure_t <= TimeWindow_Zoom(2));
if ~any(valid_idx_p), valid_idx_p = true(size(pure_t)); end
t_show_p = pure_t(valid_idx_p); x_show_p = pure_x(valid_idx_p) - pure_x(find(valid_idx_p,1));
actual_t_min = t_show_p(1); actual_t_max = t_show_p(end);
plot_handles3 = []; plot_labels3 = {};
yyaxis left; hold on;
for iVar = 1:length(InvestigateVars)
    if ~isempty(SampleTraj{iVar})
        t_vec = SampleTraj_T{iVar}; x_vec = SampleTraj{iVar}(:,1) * 1e-3; 
        valid_idx = (t_vec >= TimeWindow_Zoom(1)) & (t_vec <= TimeWindow_Zoom(2));
        if ~any(valid_idx), valid_idx = true(size(t_vec)); end
        t_show = t_vec(valid_idx); x_show = x_vec(valid_idx); x_show = x_show - x_show(1); 
        h = plot(t_show, x_show, '-', 'Color', [Colors(iVar,:), 0.8], 'LineWidth', 1.5);
        plot_handles3 = [plot_handles3, h]; plot_labels3{end+1} = strrep(InvestigateVars{iVar},'_',' '); 
    end
end
ylabel('Trapped \Delta X (\mu m)', 'FontWeight', 'bold', 'Color', 'k');
ax = gca; ax.YAxis(1).Color = 'k'; 
set(gca, 'FontSize', FontSize_Axis, 'LineWidth', 1.5, 'TickDir', 'in');
yyaxis right; hold on;
h_p = plot(t_show_p, x_show_p, '-', 'Color', [0.7 0.7 0.7 0.5], 'LineWidth', 1.5);
plot_handles3 = [plot_handles3, h_p]; plot_labels3{end+1} = 'Free Diffusion (Right Axis)';
ylabel('Free \Delta X (\mu m)', 'FontWeight', 'bold', 'Color', [0.5 0.5 0.5]);
ax.YAxis(2).Color = [0.5 0.5 0.5];
xlabel('Time t (s)', 'FontWeight', 'bold');
title('(c) Time-Domain X(t) [Dual Axis]', 'FontSize', 14);
legend(plot_handles3, plot_labels3, 'Location', 'best', 'FontSize', 10, 'Box', 'off');
xlim([actual_t_min, actual_t_max]); box on;
% ---------------------------------------------------------------------
% 子图 (d): 空间形态学特征提取与终极内嵌排版
% ---------------------------------------------------------------------
% 使用极其紧凑的 2x4 内网格
t_inner = tiledlayout(t_outer, 2, 4, 'TileSpacing', 'tight', 'Padding', 'tight');
t_inner.Layout.Tile = 4; 
Traj_Centered_Cell = cell(1, length(InvestigateVars));
max_bound = 0; 
% 全局坐标系极值锁定
for iVar = 1:length(InvestigateVars)
    if ~isempty(SampleTraj{iVar})
        t_vec = SampleTraj_T{iVar}; traj = SampleTraj{iVar} * 1e-3; 
        valid_idx = (t_vec >= TimeWindow_Zoom(1)) & (t_vec <= TimeWindow_Zoom(2));
        if ~any(valid_idx), valid_idx = true(size(t_vec)); end
        
        traj_show = traj(valid_idx, :); 
        traj_centered = traj_show - mean(traj_show, 1); 
        Traj_Centered_Cell{iVar} = traj_centered; 
        
        current_max = max(abs(traj_centered(:)));
        if current_max > max_bound, max_bound = current_max; end
    end
end
max_bound = max_bound * 1.05; % 5% 呼吸空间
% --- 4.1 主重叠视图 (霸占左侧 2x2 格子) ---
ax_main = nexttile(t_inner, 1, [2, 2]); 
hold on; box on;
set(ax_main, 'FontSize', FontSize_Axis, 'LineWidth', 1.5, 'TickDir', 'in');
plot_handles4 = []; plot_labels4 = {};
for iVar = 1:length(InvestigateVars)
    if ~isempty(Traj_Centered_Cell{iVar})
        traj_c = Traj_Centered_Cell{iVar};
        h = plot(traj_c(:,1), traj_c(:,2), '.-', 'Color', [Colors(iVar,:), 0.8], 'MarkerSize', 6, 'LineWidth', 1.2);
        plot_handles4 = [plot_handles4, h]; plot_labels4{end+1} = strrep(InvestigateVars{iVar},'_',' '); 
    end
end
plot(0, 0, 'kx', 'MarkerSize', 12, 'LineWidth', 2);
xlabel('X (\mu m)', 'FontWeight', 'bold'); ylabel('Y (\mu m)', 'FontWeight', 'bold');
title('(d) Morphology (Overlaid)', 'FontSize', 14);
legend(plot_handles4, plot_labels4, 'Location', 'best', 'FontSize', 10, 'Box', 'off');
axis(ax_main, 'equal'); 
xlim(ax_main, [-max_bound, max_bound]); 
ylim(ax_main, [-max_bound, max_bound]); 
% --- 4.2 卫星图 (右侧紧凑排列，关联标题与同步颜色) ---
inset_tiles = [3, 4, 7, 8];
for iVar = 1:length(InvestigateVars)
    ax_sub = nexttile(t_inner, inset_tiles(iVar)); 
    hold on; box on;
    
    if ~isempty(Traj_Centered_Cell{iVar})
        traj_c = Traj_Centered_Cell{iVar};
        plot(traj_c(:,1), traj_c(:,2), '.-', 'Color', [Colors(iVar,:), 0.8], 'MarkerSize', 4, 'LineWidth', 1.0);
        plot(0, 0, 'kx', 'MarkerSize', 6, 'LineWidth', 1.5);
    end
    
    % 绝对等比例尺度继承
    axis(ax_sub, 'equal'); 
    xlim(ax_sub, [-max_bound, max_bound]); 
    ylim(ax_sub, [-max_bound, max_bound]); 
    
    % 坐标轴刻度与单位
    xlabel('X (\mu m)', 'FontSize', 9, 'FontWeight', 'bold', 'Color', 'k');
    ylabel('Y (\mu m)', 'FontSize', 9, 'FontWeight', 'bold', 'Color', 'k');
    set(ax_sub, 'FontSize', 8, 'TickDir', 'in', 'LineWidth', 1.0);
    
    % ++ 动态、不硬编码、纯黑加粗的子图标识 ++
    raw_title = strrep(InvestigateVars{iVar}, '_', ' '); 
    linked_title = sprintf('(d)-%d %s', iVar, raw_title);
    title(linked_title, 'FontSize', 11, 'Color', 'k', 'FontWeight', 'normal');
end

%% =====================================================================
% [5] 自动化存图模块：基于特征变量提取生成目录与文件
% =====================================================================
fprintf('\n[INFO] 正在执行图表自动保存序列...\n');

% 基于主控变量和研究变量生成具有高度标识度的文件夹名
ctrl_str = strjoin(ControlVars, '_');
inv_str  = strjoin(InvestigateVars, '_');
folderName = sprintf('[%s][%s]', ctrl_str, inv_str);

% 防止路径长度溢出引发操作系统报错
if length(folderName) > 150
    folderName = [folderName(1:145), '...]']; 
end
% 智能清理操作系统不支持的非法字符
folderName = regexprep(folderName, '[\\/:*?"<>|]', '_'); 

% 定位存储并创建目录
saveDir = fullfile(pwd, 'Saved_Figures', folderName);
if ~exist(saveDir, 'dir')
    mkdir(saveDir);
end

% 获取当前活动图像句柄（即刚生成的全景图）
fig_main = gcf;

% 提取大图名字并进行字符串消毒
figName = fig_main.Name;
if isempty(figName)
    figName = 'Comprehensive_Dynamics_Panel';
end
safeFigName = regexprep(figName, '\s*\(.*?\)', ''); % 剔除括号及其内容
safeFigName = strrep(safeFigName, ' ', '_');        % 空格替换为下划线
safeFigName = regexprep(safeFigName, '[\\/:*?"<>|()]', ''); % 清理残余非法字符

% 导出双格式 (.fig 交互矢量原文件 + .jpg 300DPI 出版级栅格图)
figPath = fullfile(saveDir, [safeFigName, '.fig']);
jpgPath = fullfile(saveDir, [safeFigName, '.jpg']);

% 保存操作
savefig(fig_main, figPath);
try
    exportgraphics(fig_main, jpgPath, 'Resolution', 300);
catch
    % 若 MATLAB 低版本不支持 exportgraphics，启用旧版渲染器回退策略
    print(fig_main, jpgPath, '-djpeg', '-r300');
end

fprintf('[INFO] 图表已成功保存至: %s\n', saveDir);
fprintf('[INFO] 全景分析图表渲染完成 (Analysis execution finished).\n');
end