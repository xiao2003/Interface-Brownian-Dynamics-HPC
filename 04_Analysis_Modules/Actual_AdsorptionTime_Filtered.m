function Actual_AdsorptionTime_Filtered()
% =========================================================================
% 功能描述：整合分析单分子微观与宏观动力学，生成综合全景图表。
% 进阶功能：
% 1. 全自动智能数据寻址（优先分析根目录 analysis，备用最新 Task）。
% 2. 绘制 2x2 宏观动力学全景图（含极度严谨的 PDF 手动归一化）。
% 3. 自动生成 2x2 四宫格同步物理底层动画（预设缺陷基底 + 独立秒表）。
% 4. 智能播放倍速控制，严格锚定物理流逝时间。
% =========================================================================
clc; clear; close all;
%% --- 1. 实验参数与环境配置 ---
ControlVars     = {'Tads0.0010_', 'adR1_', 'DS60_', 'ratio_0k', 'jf1e+08'}; 
InvestigateVars = {'PowerLaw_TI-2.5', 'PowerLaw_TI-1.5', 'Exp', 'Uniform'};
Colors = [0.00, 0.45, 0.74; 0.85, 0.33, 0.10; 0.93, 0.69, 0.13; 0.49, 0.18, 0.56];
NumBins       = 80;    
Ts_Target     = 0.02;  
MaxLagFrames  = 50;    
FontSize_Axis = 13;    
TimeWindow_Zoom = [0, inf];  

% +++ 【视频播放倍速控制】 +++
% 设为 10 代表 10 倍速。1000秒仿真轨迹将精准生成 100秒 的视频。
Video_Playback_Speed = 10; 
% ++++++++++++++++++++++++++++++++++

%% --- 2. 数据目录定位与检索 (全自动智能寻址版) ---
baseResultDir = fullfile(pwd, 'Simulation_Results');
Target_Dir = fullfile(pwd, 'analysis'); % 优先在当前目录找 analysis 文件夹

if ~exist(Target_Dir, 'dir') && exist(baseResultDir, 'dir')
    taskDirs = dir(fullfile(baseResultDir, 'Task_*'));
    if ~isempty(taskDirs)
        [~, idx] = max([taskDirs.datenum]);
        Target_Dir = fullfile(baseResultDir, taskDirs(idx).name);
        fprintf('[INFO] 未找到 analysis 文件夹，已重定向到最新数据: %s\n', taskDirs(idx).name);
    end
end

if ~exist(Target_Dir, 'dir')
    error('找不到数据文件夹！请确保当前目录下存在 analysis 文件夹，或 Simulation_Results 存在 Task_ 文件夹。'); 
end

fprintf('[INFO] 成功锁定并读取数据目录: %s\n', Target_Dir);

all_items = dir(Target_Dir);
subfolders = all_items([all_items.isdir] & ~ismember({all_items.name}, {'.','..'}));

%% --- 3. 初始化数据存储阵列 ---
T_ads_All     = cell(1, length(InvestigateVars)); 
MSD_Sum       = zeros(MaxLagFrames, length(InvestigateVars));
MSD_Count     = zeros(MaxLagFrames, length(InvestigateVars));
SampleTraj    = cell(1, length(InvestigateVars)); 
SampleTraj_T  = cell(1, length(InvestigateVars)); 
RawTraps_Cell = cell(1, length(InvestigateVars)); 

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
                    RawTraps_Cell{iVar} = pos(:, 1:2); 
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
% 绘制综合动力学全景图 
% =====================================================================
fig_main = figure('Name', 'Comprehensive Single Molecule Dynamics', 'Position', [50, 50, 1600, 850]);
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
t_inner = tiledlayout(t_outer, 2, 4, 'TileSpacing', 'tight', 'Padding', 'tight');
t_inner.Layout.Tile = 4; 
Traj_Centered_Cell = cell(1, length(InvestigateVars));
max_bound = 0; 
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
max_bound = max_bound * 1.05; 

% --- 4.1 主重叠视图 ---
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

% --- 4.2 卫星图 ---
inset_tiles = [3, 4, 7, 8];
for iVar = 1:length(InvestigateVars)
    ax_sub = nexttile(t_inner, inset_tiles(iVar)); 
    hold on; box on;
    if ~isempty(Traj_Centered_Cell{iVar})
        traj_c = Traj_Centered_Cell{iVar};
        plot(traj_c(:,1), traj_c(:,2), '.-', 'Color', [Colors(iVar,:), 0.8], 'MarkerSize', 4, 'LineWidth', 1.0);
        plot(0, 0, 'kx', 'MarkerSize', 6, 'LineWidth', 1.5);
    end
    axis(ax_sub, 'equal'); 
    xlim(ax_sub, [-max_bound, max_bound]); 
    ylim(ax_sub, [-max_bound, max_bound]); 
    xlabel('X (\mu m)', 'FontSize', 9, 'FontWeight', 'bold', 'Color', 'k');
    ylabel('Y (\mu m)', 'FontSize', 9, 'FontWeight', 'bold', 'Color', 'k');
    set(ax_sub, 'FontSize', 8, 'TickDir', 'in', 'LineWidth', 1.0);
    raw_title = strrep(InvestigateVars{iVar}, '_', ' '); 
    linked_title = sprintf('(d)-%d %s', iVar, raw_title);
    title(linked_title, 'FontSize', 11, 'Color', 'k', 'FontWeight', 'normal');
end

%% =====================================================================
% [5] 自动化存图模块
% =====================================================================
fprintf('\n[INFO] 正在执行图表自动保存序列...\n');
ctrl_str = strjoin(ControlVars, '_');
inv_str  = strjoin(InvestigateVars, '_');
folderName = sprintf('[%s][%s]', ctrl_str, inv_str);
if length(folderName) > 150, folderName = [folderName(1:145), '...]']; end
folderName = regexprep(folderName, '[\\/:*?"<>|]', '_'); 
saveDir = fullfile(pwd, 'Saved_Figures', folderName);
if ~exist(saveDir, 'dir'), mkdir(saveDir); end

figName = fig_main.Name;
if isempty(figName), figName = 'Comprehensive_Dynamics_Panel'; end
safeFigName = regexprep(figName, '\s*\(.*?\)', ''); 
safeFigName = strrep(safeFigName, ' ', '_');        
safeFigName = regexprep(safeFigName, '[\\/:*?"<>|()]', ''); 

figPath = fullfile(saveDir, [safeFigName, '.fig']);
jpgPath = fullfile(saveDir, [safeFigName, '.jpg']);
savefig(fig_main, figPath);
try
    exportgraphics(fig_main, jpgPath, 'Resolution', 300);
catch
    print(fig_main, jpgPath, '-djpeg', '-r300');
end
fprintf('[INFO] 图表已成功保存至: %s\n', saveDir);

%% =====================================================================
% [6] 自动化四宫格同步物理动画：智能倍速锚定引擎 (含时长预测与单行进度条)
% =========================================================================
fprintf('\n[INFO] 正在筹备视频渲染引擎...\n');

% 1. 计算全局最长帧数
N_frames_all = zeros(1, length(InvestigateVars));
for iVar = 1:length(InvestigateVars)
    if ~isempty(Traj_Centered_Cell{iVar})
        N_frames_all(iVar) = size(Traj_Centered_Cell{iVar}, 1);
    end
end
max_N_frames = max(N_frames_all);

if max_N_frames > 0
    % 2. 智能倍速与时长预测
    Physical_Total_Time = max_N_frames * Ts_Target; % 物理总时长 (s)
    Target_Video_Duration = Physical_Total_Time / Video_Playback_Speed; % 预期视频时长 (s)
    Target_Video_Frames = max(10, round(Target_Video_Duration * 30)); % 目标总帧数 (30fps)
    skip_step = max(1, floor(max_N_frames / Target_Video_Frames));    
    
    frame_indices = 1:skip_step:max_N_frames;
    total_render_frames = length(frame_indices);
    Actual_Video_Len = total_render_frames / 30; % 最终生成的视频精准播放时长

    fprintf('  -> 物理仿真总时长: %.2f s\n', Physical_Total_Time);
    fprintf('  -> 设定播放倍速: %d x\n', Video_Playback_Speed);
    fprintf('  -> 预期视频总长: %.2f s (约 %d 帧)\n', Actual_Video_Len, total_render_frames);
    fprintf('--------------------------------------------------\n');

    % 3. 视频写入器配置
    videoPath = fullfile(saveDir, sprintf('Animation_4Panel_%dxSpeed.mp4', Video_Playback_Speed));
    try
        v = VideoWriter(videoPath, 'MPEG-4');
    catch
        v = VideoWriter(videoPath, 'Motion JPEG AVI');
    end
    v.FrameRate = 30; v.Quality = 85; open(v);

    % 4. 显卡硬件加速配置 (Visible must be 'on' for Hardware OpenGL)
    fig_anim = figure('Visible', 'on', 'Color', 'w', 'Position', [100, 100, 1000, 1000], 'Renderer', 'opengl');
    t_anim = tiledlayout(fig_anim, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    % 5. 预分配句柄 (代码逻辑同前，此处略，保持你现有的初始化部分)
    ax_list = gobjects(1, length(InvestigateVars));
    h_trail_list = gobjects(1, length(InvestigateVars));
    h_lit_list = gobjects(1, length(InvestigateVars));
    h_part_list = gobjects(1, length(InvestigateVars));
    h_timer_list = gobjects(1, length(InvestigateVars));
    trap_sites_cell = cell(1, length(InvestigateVars));

    for iVar = 1:length(InvestigateVars)
        ax_list(iVar) = nexttile(t_anim); hold(ax_list(iVar), 'on'); box(ax_list(iVar), 'on');
        if isempty(Traj_Centered_Cell{iVar}), title(ax_list(iVar), 'No Data'); continue; end
        
        % 绘制背景与缺陷 (逻辑同前)
        bg_spacing = max_bound / 30; [Xg, Yg] = meshgrid(-max_bound:bg_spacing:max_bound);
        scatter(ax_list(iVar), Xg(:), Yg(:), 3, [0.9 0.9 0.9], 'filled');
        raw_pos_um = RawTraps_Cell{iVar} * 1e-3;
        valid_idx = (SampleTraj_T{iVar} >= TimeWindow_Zoom(1)) & (SampleTraj_T{iVar} <= TimeWindow_Zoom(2));
        offset_center = mean(SampleTraj{iVar}(valid_idx, :) * 1e-3, 1);
        trap_sites = unique(round((raw_pos_um - offset_center) * 1e5) / 1e5, 'rows');
        trap_sites_cell{iVar} = trap_sites;
        scatter(ax_list(iVar), trap_sites(:,1), trap_sites(:,2), 5, [0.75 0.75 0.75], 'filled');
        
        h_trail_list(iVar) = plot(ax_list(iVar), NaN, NaN, '-', 'Color', [Colors(iVar,:), 0.4], 'LineWidth', 1.0);
        h_lit_list(iVar)   = plot(ax_list(iVar), NaN, NaN, 'o', 'MarkerFaceColor', [1 0.7 0], 'MarkerEdgeColor', [1 0.5 0], 'MarkerSize', 12);
        h_part_list(iVar)  = plot(ax_list(iVar), NaN, NaN, 'o', 'MarkerFaceColor', Colors(iVar,:), 'MarkerEdgeColor', 'w', 'MarkerSize', 6, 'LineWidth', 1.0);
        h_timer_list(iVar) = text(ax_list(iVar), max_bound*0.95, max_bound*0.80, 'Status: Moving', 'FontSize', 12, 'FontWeight', 'bold', 'Color', [0.5 0.5 0.5], ...
            'HorizontalAlignment', 'right', 'BackgroundColor', [1 1 1 0.85], 'EdgeColor', 'k', 'Margin', 5);
        axis(ax_list(iVar), 'equal'); xlim(ax_list(iVar), [-max_bound, max_bound]); ylim(ax_list(iVar), [-max_bound, max_bound]);
    end

    % 7. 执行渲染与单行进度监控
    trap_time_counters = zeros(1, 4); prev_f_list = ones(1, 4);
    msg_len = 0; anim_startTime = tic;

    for iter = 1:total_render_frames
        f = frame_indices(iter);
        for iVar = 1:length(InvestigateVars)
            if isempty(Traj_Centered_Cell{iVar}), continue; end
            traj_c = Traj_Centered_Cell{iVar}; t_vec = SampleTraj_T{iVar};
            curr_f = min(f, size(traj_c,1));
            dt = t_vec(curr_f) - t_vec(prev_f_list(iVar));
            prev_f_list(iVar) = curr_f;
            curr_pos = traj_c(curr_f, :);

            set(h_trail_list(iVar), 'XData', traj_c(1:curr_f, 1), 'YData', traj_c(1:curr_f, 2));
            set(h_part_list(iVar), 'XData', curr_pos(1), 'YData', curr_pos(2));
            
            trap_sites = trap_sites_cell{iVar};
            [min_sq_dist, closest_trap_idx] = min(sum((trap_sites - curr_pos).^2, 2));
            if curr_f < size(traj_c,1) && norm(traj_c(curr_f+1,:) - curr_pos) < 1e-3 && sqrt(min_sq_dist) < 0.015
                trap_time_counters(iVar) = trap_time_counters(iVar) + dt;
                set(h_lit_list(iVar), 'XData', trap_sites(closest_trap_idx,1), 'YData', trap_sites(closest_trap_idx,2));
                set(h_timer_list(iVar), 'String', sprintf('Adsorption: %5.2f s', trap_time_counters(iVar)), 'Color', [0.85 0.1 0.1]);
            else
                trap_time_counters(iVar) = 0;
                set(h_lit_list(iVar), 'XData', NaN, 'YData', NaN);
                set(h_timer_list(iVar), 'String', 'Status: Moving', 'Color', [0.5 0.5 0.5]);
            end
            title(ax_list(iVar), sprintf('%s\nTime: %.2f s', strrep(InvestigateVars{iVar},'_',' '), t_vec(curr_f)), 'FontSize', 12);
        end

        writeVideo(v, getframe(fig_anim));
        
        % 进度条逻辑
        elap = toc(anim_startTime);
        pct = (iter / total_render_frames) * 100;
        remTime = elap * (total_render_frames - iter) / iter;
        strToPrint = sprintf('  -> 渲染进度: [%.1f%%] | 已用: %.1fs | 预计剩余: %.1fs', pct, elap, remTime);
        fprintf(repmat('\b', 1, msg_len)); fprintf('%s', strToPrint); msg_len = numel(strToPrint);
    end

    close(v); close(fig_anim);
    fprintf('\n\n[INFO] 渲染结束。视频播放时长: %.2f s\n', Actual_Video_Len);
end