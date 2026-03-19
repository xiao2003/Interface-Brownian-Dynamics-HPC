function Verify_Figure6()
% =========================================================================
% 功能：严格复现 Nature Supplementary Figure 6 (b) 和 (c)
% 验证宏观扩散方程：D ~ l_D^2 * <\tau>^{-1}
% =========================================================================
clc; clear; close all;

%% 1. 参数与路径配置
Target_Tads = 0.04; % 平均吸附时间 40ms
ControlVars = {'Exp', sprintf('Tads%.4f_', Target_Tads), 'adR1_', 'ratio_0k', 'jf1e+08'};
DS_Values   = [10, 20, 30, 40, 60, 80, 100];
InvestigateVars = arrayfun(@(x) sprintf('DS%d_', x), DS_Values, 'UniformOutput', false);

% 使用与你原来一致的高级配色库
Colors = lines(length(DS_Values));

DataDir = fullfile(pwd, 'Simulation_Results');
taskDirs = dir(fullfile(DataDir, 'Task_*'));
[~, idx] = max([taskDirs.datenum]);
Target_Dir = fullfile(DataDir, taskDirs(idx).name);
fprintf('[INFO] 读取最新数据集目录: %s\n', taskDirs(idx).name);

all_items = dir(Target_Dir);
subfolders = all_items([all_items.isdir] & ~ismember({all_items.name}, {'.','..'}));

%% 2. 提取每个 DS 下的扩散系数 D
D_array = NaN(1, length(DS_Values));
Ts_Target = 0.02;
MaxLagFrames = 50;
calc_steps = 1:MaxLagFrames;

for i = 1:length(InvestigateVars)
    current_var = InvestigateVars{i};
    match_mask = true(1, length(subfolders));
    for c = 1:length(ControlVars)
        match_mask = match_mask & contains({subfolders.name}, ControlVars{c}); 
    end
    match_mask = match_mask & contains({subfolders.name}, current_var);
    matching_folders = subfolders(match_mask);
    
    if isempty(matching_folders), continue; end
    
    % 提取 MSD
    RepMSDs = [];
    for f = 1:length(matching_folders)
        folder_path = fullfile(Target_Dir, matching_folders(f).name);
        mat_files = dir(fullfile(folder_path, '*.mat'));
        for rep_f = 1:length(mat_files)
            data = load(fullfile(folder_path, mat_files(rep_f).name), 'positionlist');
            if isfield(data, 'positionlist')
                pos = data.positionlist;
                frames = double(pos(:, 3));
                [u_frames, ~, idx] = unique(frames);
                mean_X = accumarray(idx, pos(:, 1)) ./ accumarray(idx, 1);
                mean_Y = accumarray(idx, pos(:, 2)) ./ accumarray(idx, 1);
                
                max_f = max(u_frames); min_f = min(u_frames);
                full_len = max_f - min_f + 1;
                contig_X = NaN(full_len, 1); contig_Y = NaN(full_len, 1);
                frame_indices = u_frames - min_f + 1;
                contig_X(frame_indices) = mean_X; contig_Y(frame_indices) = mean_Y;
                
                temp_msd = NaN(1, length(calc_steps));
                for s_idx = 1:length(calc_steps)
                    step = calc_steps(s_idx);
                    if full_len > step
                        sq_disp = (contig_X(1+step:end) - contig_X(1:end-step)).^2 + ...
                                  (contig_Y(1+step:end) - contig_Y(1:end-step)).^2;
                        valid_sq = sq_disp(~isnan(sq_disp));
                        if ~isempty(valid_sq), temp_msd(s_idx) = mean(valid_sq); end
                    end
                end
                RepMSDs = [RepMSDs; temp_msd]; %#ok<AGROW>
            end
        end
    end
    
    % 拟合扩散系数 D (MSD = 4*D*t)
    if ~isempty(RepMSDs)
        msd_mean = mean(RepMSDs, 1, 'omitnan');
        X_time = calc_steps * Ts_Target;
        Y_mean_m2 = msd_mean * 1e-18; % 从 nm^2 转换为 m^2
        
        % 截取前 20 个点进行线性拟合
        fit_idx = X_time <= 1.0; 
        coef = polyfit(X_time(fit_idx), Y_mean_m2(fit_idx), 1);
        D_array(i) = coef(1) / 4; 
    end
end

%% 3. 绘制 1x2 验证图版
fig = figure('Name', 'Validate_Nature_Fig6', 'Position', [100, 100, 1200, 500], 'Color', 'w');
t = tiledlayout(1, 2, 'TileSpacing', 'normal', 'Padding', 'compact');

% -------------------------------------------------------------------------
% [图 b]: D vs l_D
% -------------------------------------------------------------------------
ax1 = nexttile(t); hold on; box on;
set(ax1, 'XScale', 'log', 'YScale', 'log', 'FontSize', 15, 'LineWidth', 1.5, 'TickDir', 'in');

% 绘制理论斜率线 (Slope = 2)
ref_x = [min(DS_Values), max(DS_Values)];
ref_y = D_array(1) * (ref_x / ref_x(1)).^2; 
plot(ref_x, ref_y, 'k--', 'LineWidth', 2);

% 绘制散点
for i = 1:length(DS_Values)
    if ~isnan(D_array(i))
        scatter(ax1, DS_Values(i), D_array(i), 100, Colors(i,:), 'filled', 'MarkerEdgeColor', 'k');
    end
end

xlabel('I_D (nm)', 'FontSize', 18, 'FontWeight', 'bold');
ylabel('D (m^2s^{-1})', 'FontSize', 18, 'FontWeight', 'bold');
title('(b) Diffusion vs Inter-defect distance', 'FontSize', 16);
text(ax1, 0.8, 0.9, 'Slope = 2', 'Units', 'normalized', 'FontSize', 16, 'FontWeight', 'bold');
xlim([8, 120]); ylim([1e-16, 1e-12]);

% -------------------------------------------------------------------------
% [图 c]: D vs l_D^2 * <\tau>^{-1}
% -------------------------------------------------------------------------
ax2 = nexttile(t); hold on; box on;
set(ax2, 'XScale', 'log', 'YScale', 'log', 'FontSize', 15, 'LineWidth', 1.5, 'TickDir', 'in');

% +++ 【核心修正】：将 DS_Values 从 nm 转换为 m，使得横轴单位变为 m^2/s +++
X_master = ((DS_Values * 1e-9).^2) / Target_Tads; 

% 绘制理论斜率线 (Slope = 1)
ref_x2 = [min(X_master), max(X_master)];
ref_y2 = D_array(1) * (ref_x2 / ref_x2(1)).^1; 
plot(ref_x2, ref_y2, 'k--', 'LineWidth', 2);

% 绘制散点
for i = 1:length(DS_Values)
    if ~isnan(D_array(i))
        scatter(ax2, X_master(i), D_array(i), 100, Colors(i,:), 'filled', 'MarkerEdgeColor', 'k');
    end
end

% +++ 更改 X 轴 Label 为国际标准单位，并对齐范围 +++
xlabel('I_D^2 <\tau>^{-1} (m^2s^{-1})', 'FontSize', 18, 'FontWeight', 'bold');
ylabel('D (m^2s^{-1})', 'FontSize', 18, 'FontWeight', 'bold');
title('(c) Master Curve', 'FontSize', 16);
text(ax2, 0.8, 0.9, 'Slope = 1', 'Units', 'normalized', 'FontSize', 16, 'FontWeight', 'bold');

% 将 X 轴范围严格锁定在原论文的 10^-16 到 10^-11 之间
xlim([1e-16, 1e-11]); ylim([1e-16, 1e-12]);

fprintf('>>> Fig 6 验证图绘制完成！\n');
end