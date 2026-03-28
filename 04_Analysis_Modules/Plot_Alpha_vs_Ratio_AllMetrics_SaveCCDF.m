function Plot_Alpha_vs_Ratio_AllMetrics_SaveCCDF()
% =========================================================================
% Plot_Alpha_vs_Ratio_AllMetrics_SaveCCDF
% -------------------------------------------------------------------------
% 四宫格：
%   (a) Conditional Asymmetry
%   (b) Central-Peak / Stagnation Fraction
%   (c) Adsorption-Time CCDF / Survival Curve   <-- 新版本左下角
%   (d) Effective Transport Asymmetry
%
% 自动保存：
%   Combined_Panel.fig/.jpg
%   Conditional_Asymmetry.fig/.jpg
%   Central_Peak_Stagnation.fig/.jpg
%   Adsorption_Time_CCDF.fig/.jpg
%   Effective_Transport_Asymmetry.fig/.jpg
%   Raw_Metrics.mat
%
% 说明：
%   - 优先读取 analysis 文件夹
%   - 若无 analysis，则自动跳转到最新 Simulation_Results/Task_*
%   - 保持你原来 ratio -> n_vis 的处理逻辑
% =========================================================================
clc; clear; close all;

%% ========================= 1. 参数配置 =========================
ControlVars = {'Tads0.0010_', 'adR1_', 'DS20_'};

DistModes   = { ...
    'PowerLaw_TI-2.5', ...
    'PowerLaw_TI-1.9', ...
    'PowerLaw_TI-1.5', ...
    'PowerLaw_TI-1.1', ...
    'PowerLaw_TI-0.9', ...
    'PowerLaw_TI-0.5', ...
    'PowerLaw_TI0.5',  ...
    'PowerLaw_TI1.5',  ...
    'PowerLaw_TI2.5',  ...
    'Exp', ...
    'Uniform'};

Colors = lines(length(DistModes));
Marker_Size = 80;
LineWidth_Base = 2.2;

DeltaFactor   = 1.0;   % delta = DeltaFactor * adR
MinTotalCount = 1;     % 稀疏点不丢
D_val         = 1e-10; % 与主程序一致

%% ========================= 2. 自动定位数据源 =========================
baseResultDir = fullfile(pwd, 'Simulation_Results');
Target_Dir    = fullfile(pwd, 'analysis');

if ~exist(Target_Dir, 'dir') && exist(baseResultDir, 'dir')
    taskDirs = dir(fullfile(baseResultDir, 'Task_*'));
    if ~isempty(taskDirs)
        [~, idx] = max([taskDirs.datenum]);
        Target_Dir = fullfile(baseResultDir, taskDirs(idx).name);
        fprintf('>>> 未找到 analysis 文件夹，已重定向到最新数据: %s\n', taskDirs(idx).name);
    end
end

if ~exist(Target_Dir, 'dir')
    error('找不到数据文件夹！请确保当前目录下存在 analysis 文件夹，或 Simulation_Results 存在 Task_* 文件夹。');
end

fprintf('>>> 读取数据集目录: %s\n', Target_Dir);

all_items  = dir(Target_Dir);
subfolders = all_items([all_items.isdir] & ~ismember({all_items.name}, {'.','..'}));

%% ========================= 3. 初始化数据容器 =========================
MetricNames = {'xi_cond', 'phi0', 'xi_eff'};

AllMetricData = struct();
AdsCCDFData   = struct();

for m = 1:numel(MetricNames)
    metric_name = MetricNames{m};
    for i = 1:length(DistModes)
        dist_name = matlab.lang.makeValidName(DistModes{i});
        AllMetricData.(metric_name).(dist_name).X = [];
        AllMetricData.(metric_name).(dist_name).Y = [];
    end
end

for i = 1:length(DistModes)
    dist_name = matlab.lang.makeValidName(DistModes{i});
    AdsCCDFData.(dist_name).tau_ads = [];
end

global_zero_mapped_val = 1e-8;

%% ========================= 4. 核心提取循环 =========================
for i = 1:length(DistModes)
    current_dist = DistModes{i};
    fprintf('[+] 正在分析分布模式: %s\n', current_dist);

    match_mask = true(1, length(subfolders));
    for c = 1:length(ControlVars)
        match_mask = match_mask & contains({subfolders.name}, ControlVars{c});
    end
    match_mask = match_mask & contains({subfolders.name}, current_dist);
    matching_folders = subfolders(match_mask);

    if isempty(matching_folders)
        fprintf('    -> 无匹配文件夹。\n');
        continue;
    end

    Ratio_DataMap = containers.Map('KeyType', 'double', 'ValueType', 'any');
    Ads_DataMap   = containers.Map('KeyType', 'double', 'ValueType', 'any');

    for f = 1:length(matching_folders)
        folder_name = matching_folders(f).name;
        folder_path = fullfile(Target_Dir, folder_name);

        % ===== 保持你原来的 regexp 解析方式 =====
        tokens_n    = regexp(folder_name, 'ratio_([0-9\.eE\-]+)k', 'tokens');
        if isempty(tokens_n), continue; end
        n_val = str2double(tokens_n{1}{1});

        tokens_jf   = regexp(folder_name, 'jf([0-9\.eE\-\+]+)_', 'tokens');
        tokens_adR  = regexp(folder_name, 'adR([0-9\.eE\-\+]+)_', 'tokens');
        tokens_ds   = regexp(folder_name, 'DS([0-9\.eE\-\+]+)_', 'tokens');
        tokens_Ts   = regexp(folder_name, 'Ts([0-9\.eE\-\+]+)_', 'tokens');
        tokens_Tads = regexp(folder_name, 'Tads([0-9\.eE\-\+]+)_', 'tokens');

        if ~isempty(tokens_jf),   jf_val   = str2double(tokens_jf{1}{1});   else, jf_val   = 1e8;   end
        if ~isempty(tokens_adR),  adR_val  = str2double(tokens_adR{1}{1});  else, adR_val  = 1.0;   end
        if ~isempty(tokens_ds),   ds_val   = str2double(tokens_ds{1}{1});   else, ds_val   = 20.0;  end
        if ~isempty(tokens_Ts),   Ts_val   = str2double(tokens_Ts{1}{1});   else, Ts_val   = 0.02;  end
        if ~isempty(tokens_Tads), Tads_val = str2double(tokens_Tads{1}{1}); else, Tads_val = 0.001; end

        % ===== 保持你原来的 n_vis 逻辑 =====
        k_nm   = sqrt(2 * D_val / jf_val) * 1e9;
        n_geo  = (adR_val * k_nm) / (ds_val^2);
        t_free = (ds_val * 1e-9)^2 / (4 * D_val);
        M_eff  = Ts_val / (t_free + Tads_val);

        if M_eff > 0
            n_vis = n_geo / sqrt(M_eff);
        else
            n_vis = NaN;
        end

        if isfinite(n_vis) && n_vis > 0
            scaled_X = n_val / n_vis;
        else
            scaled_X = n_val;
        end

        if scaled_X > 0
            scaled_X = str2double(sprintf('%.5g', scaled_X));
        end

        mat_files = dir(fullfile(folder_path, '*.mat'));
        dx_temp   = [];
        tau_temp  = [];

        for rep_f = 1:length(mat_files)
            file_path = fullfile(folder_path, mat_files(rep_f).name);

            % ---------- positionlist ----------
            try
                data = load(file_path);
            catch
                continue;
            end

            if isfield(data, 'positionlist') && size(data.positionlist, 2) >= 3
                pos = data.positionlist;
                frames = double(pos(:,3));

                [~, ~, idx] = unique(frames);
                mean_X = accumarray(idx, pos(:,1)) ./ accumarray(idx, 1);

                if numel(mean_X) >= 2
                    dx_now = mean_X(2:end) - mean_X(1:end-1);
                    dx_temp = [dx_temp; dx_now(:)]; %#ok<AGROW>
                end
            end

            % ---------- 吸附时间历史 ----------
            % 尽量兼容你可能用过的变量名
            if isfield(data, 't_ads_history')
                tau_here = data.t_ads_history(:);
            elseif isfield(data, 't_ads')
                tau_here = data.t_ads(:);
            elseif isfield(data, 'adsorption_times')
                tau_here = data.adsorption_times(:);
            else
                tau_here = [];
            end

            if ~isempty(tau_here)
                tau_here = tau_here(isfinite(tau_here) & tau_here > 0);
                tau_temp = [tau_temp; tau_here]; %#ok<AGROW>
            end
        end

        if isKey(Ratio_DataMap, scaled_X)
            Ratio_DataMap(scaled_X) = [Ratio_DataMap(scaled_X); dx_temp];
        else
            Ratio_DataMap(scaled_X) = dx_temp;
        end

        if isKey(Ads_DataMap, scaled_X)
            Ads_DataMap(scaled_X) = [Ads_DataMap(scaled_X); tau_temp];
        else
            Ads_DataMap(scaled_X) = tau_temp;
        end
    end

    if isempty(keys(Ratio_DataMap))
        continue;
    end

    unique_ratios = cell2mat(keys(Ratio_DataMap));
    unique_ratios = sort(unique_ratios);

    non_zero_ratios = unique_ratios(unique_ratios > 0);
    if ~isempty(non_zero_ratios)
        min_r = min(non_zero_ratios);
        zero_mapped_val = 10^(floor(log10(min_r)) - 1);
        global_zero_mapped_val = zero_mapped_val;
    else
        zero_mapped_val = global_zero_mapped_val;
    end

    dist_key = matlab.lang.makeValidName(current_dist);

    % ===== 计算三个主指标 =====
    for r = 1:length(unique_ratios)
        scaled_X = unique_ratios(r);
        dx_v = Ratio_DataMap(scaled_X);
        dx_v = dx_v(isfinite(dx_v));

        if numel(dx_v) < MinTotalCount
            continue;
        end

        delta_nm = DeltaFactor * adR_val;
        [xi_cond, phi0, xi_eff] = compute_main_metrics(dx_v, delta_nm);

        if scaled_X == 0
            plot_x = zero_mapped_val;
        else
            plot_x = scaled_X;
        end

        AllMetricData.xi_cond.(dist_key).X(end+1) = plot_x;
        AllMetricData.xi_cond.(dist_key).Y(end+1) = xi_cond;

        AllMetricData.phi0.(dist_key).X(end+1) = plot_x;
        AllMetricData.phi0.(dist_key).Y(end+1) = phi0;

        AllMetricData.xi_eff.(dist_key).X(end+1) = plot_x;
        AllMetricData.xi_eff.(dist_key).Y(end+1) = xi_eff;
    end

    % ===== 左下角：取 scaled_X 最接近 1 的吸附时间样本 =====
    ads_keys = cell2mat(keys(Ads_DataMap));
    ads_keys = ads_keys(isfinite(ads_keys) & ads_keys > 0);

    if ~isempty(ads_keys)
        [~, idx_best] = min(abs(log10(ads_keys) - log10(1)));
        best_key = ads_keys(idx_best);
        tau_ads = Ads_DataMap(best_key);
        tau_ads = tau_ads(isfinite(tau_ads) & tau_ads > 0);
        AdsCCDFData.(dist_key).tau_ads = tau_ads;
    end
end

%% ========================= 5. 自动建保存文件夹 =========================
ctrl_str = strjoin(ControlVars, '_');
inv_str  = 'AllMetrics_AdsCCDF';
folderName = sprintf('[%s][%s]', ctrl_str, inv_str);
if length(folderName) > 150
    folderName = [folderName(1:145), '...]'];
end
folderName = regexprep(folderName, '[\\/:*?"<>|]', '_');

saveDir = fullfile(pwd, 'Saved_Figures', folderName);
if ~exist(saveDir, 'dir')
    mkdir(saveDir);
end

%% ========================= 6. 画综合四宫格 =========================
fig_combo = figure('Name', 'Combined_Panel', 'Position', [60, 40, 1700, 1000], 'Color', 'w');
tlo = tiledlayout(2,2, 'TileSpacing', 'compact', 'Padding', 'compact');

% ---------------- (a) Conditional Asymmetry ----------------
ax1 = nexttile(tlo, 1); hold(ax1, 'on'); box(ax1, 'on');
plot_mastercurve(ax1, AllMetricData.xi_cond, DistModes, Colors, Marker_Size, LineWidth_Base);
set(ax1, 'XScale', 'log', 'FontSize', 14, 'LineWidth', 1.5, 'TickDir', 'in');
xlabel(ax1, 'Normalized Driving Force  n / n_{vis}', 'FontSize', 16, 'FontWeight', 'bold');
ylabel(ax1, 'Conditional Asymmetry  \xi_{cond}', 'FontSize', 16, 'FontWeight', 'bold');
title(ax1, 'Conditional Asymmetry', 'FontSize', 16, 'FontWeight', 'bold');
apply_axis_decor(ax1, global_zero_mapped_val, false);

% ---------------- (b) Stagnation Fraction ----------------
ax2 = nexttile(tlo, 2); hold(ax2, 'on'); box(ax2, 'on');
plot_mastercurve(ax2, AllMetricData.phi0, DistModes, Colors, Marker_Size, LineWidth_Base);
set(ax2, 'XScale', 'log', 'FontSize', 14, 'LineWidth', 1.5, 'TickDir', 'in');
xlabel(ax2, 'Normalized Driving Force  n / n_{vis}', 'FontSize', 16, 'FontWeight', 'bold');
ylabel(ax2, 'Stagnation Index  \phi_0', 'FontSize', 16, 'FontWeight', 'bold');
title(ax2, 'Central-Peak / Stagnation Fraction', 'FontSize', 16, 'FontWeight', 'bold');
apply_axis_decor(ax2, global_zero_mapped_val, true);

% ---------------- (c) Adsorption-Time CCDF ----------------
ax3 = nexttile(tlo, 3); hold(ax3, 'on'); box(ax3, 'on');
plot_adsorption_ccdf(ax3, AdsCCDFData, DistModes, Colors, Marker_Size, LineWidth_Base);
set(ax3, 'XScale', 'log', 'YScale', 'log', 'FontSize', 14, 'LineWidth', 1.5, 'TickDir', 'in');
xlabel(ax3, 'Adsorption Time  \tau_{ads} (s)', 'FontSize', 16, 'FontWeight', 'bold');
ylabel(ax3, 'CCDF  P(\tau_{ads} > t)', 'FontSize', 16, 'FontWeight', 'bold');
title(ax3, 'Adsorption-Time Survival Curve  (closest to n/n_{vis}\approx 1)', 'FontSize', 16, 'FontWeight', 'bold');
grid(ax3, 'on');

% ---------------- (d) Effective Transport Asymmetry ----------------
ax4 = nexttile(tlo, 4); hold(ax4, 'on'); box(ax4, 'on');
plot_mastercurve(ax4, AllMetricData.xi_eff, DistModes, Colors, Marker_Size, LineWidth_Base);
set(ax4, 'XScale', 'log', 'FontSize', 14, 'LineWidth', 1.5, 'TickDir', 'in');
xlabel(ax4, 'Normalized Driving Force  n / n_{vis}', 'FontSize', 16, 'FontWeight', 'bold');
ylabel(ax4, 'Effective Transport Index  \Xi_{eff}', 'FontSize', 16, 'FontWeight', 'bold');
title(ax4, 'Effective Transport Asymmetry', 'FontSize', 16, 'FontWeight', 'bold');
apply_axis_decor(ax4, global_zero_mapped_val, false);

%% ========================= 7. 自动保存 =========================
save_one_figure(fig_combo, saveDir, 'Combined_Panel');

save_axis_as_figure(ax1, saveDir, 'Conditional_Asymmetry');
save_axis_as_figure(ax2, saveDir, 'Central_Peak_Stagnation');
save_axis_as_figure(ax3, saveDir, 'Adsorption_Time_CCDF');
save_axis_as_figure(ax4, saveDir, 'Effective_Transport_Asymmetry');

save(fullfile(saveDir, 'Raw_Metrics.mat'), ...
    'AllMetricData', 'AdsCCDFData', 'ControlVars', 'DistModes');

fprintf('>>> 全部图像已自动保存至: %s\n', saveDir);

end

%% =========================================================================
function [xi_cond, phi0, xi_eff] = compute_main_metrics(dx_v, delta_nm)

dx_v = dx_v(:);
dx_v = dx_v(isfinite(dx_v));

% 1) Conditional Asymmetry
dx_R = dx_v(dx_v > 0);
dx_L = dx_v(dx_v < 0);

if isempty(dx_R), M_R = 0; else, M_R = mean(dx_R); end
if isempty(dx_L), M_L = 0; else, M_L = abs(mean(dx_L)); end

if M_R == 0 && M_L == 0
    xi_cond = 0;
else
    xi_cond = (M_R - M_L) / max(M_R, M_L);
end

% 2) Stagnation fraction
phi0 = mean(abs(dx_v) <= delta_nm);

% 3) Effective transport
dx_mov = dx_v(abs(dx_v) > delta_nm);
if isempty(dx_mov)
    xi_move = 0;
else
    dx_Rm = dx_mov(dx_mov > 0);
    dx_Lm = dx_mov(dx_mov < 0);

    if isempty(dx_Rm), M_Rm = 0; else, M_Rm = mean(dx_Rm); end
    if isempty(dx_Lm), M_Lm = 0; else, M_Lm = abs(mean(dx_Lm)); end

    if M_Rm == 0 && M_Lm == 0
        xi_move = 0;
    else
        xi_move = (M_Rm - M_Lm) / max(M_Rm, M_Lm);
    end
end

xi_eff = (1 - phi0) * xi_move;
end

%% =========================================================================
function plot_mastercurve(ax, MetricStruct, DistModes, Colors, Marker_Size, LineWidth_Base)

Markers = {'o','s','d','^','v','p','h','*','>','<','x'};
Legend_Handles = [];
Legend_Labels  = {};

maxX_local = 1;
global_zero_tick = inf;

for i = 1:length(DistModes)
    dist_key = matlab.lang.makeValidName(DistModes{i});
    X = MetricStruct.(dist_key).X;
    Y = MetricStruct.(dist_key).Y;

    if isempty(X), continue; end

    [Xuniq, ~, ic] = unique(X);
    Yavg = accumarray(ic(:), Y(:), [], @mean);

    [Xuniq, sort_idx] = sort(Xuniq);
    Yavg = Yavg(sort_idx);

    maxX_local = max(maxX_local, max(Xuniq));
    global_zero_tick = min(global_zero_tick, min(Xuniq));

    h = plot(ax, Xuniq, Yavg, '-', ...
        'Color', Colors(i,:), ...
        'LineWidth', LineWidth_Base, ...
        'Marker', Markers{mod(i-1, numel(Markers))+1}, ...
        'MarkerSize', Marker_Size/10, ...
        'MarkerFaceColor', 'w', ...
        'MarkerEdgeColor', Colors(i,:));

    Legend_Handles = [Legend_Handles, h]; %#ok<AGROW>
    Legend_Labels{end+1} = strrep(DistModes{i}, '_', ' '); %#ok<AGROW>
end

legend(ax, Legend_Handles, Legend_Labels, 'Location', 'northwest', 'FontSize', 8, 'Box', 'off');

if isfinite(global_zero_tick)
    ax.XLim = [global_zero_tick/2, maxX_local*2];
end

grid(ax, 'on');
set(ax, 'GridAlpha', 0.15);
end

%% =========================================================================
function plot_adsorption_ccdf(ax, AdsCCDFData, DistModes, Colors, Marker_Size, LineWidth_Base)

Markers = {'o','s','d','^','v','p','h','*','>','<','x'};
Legend_Handles = [];
Legend_Labels  = {};

for i = 1:length(DistModes)
    dist_key = matlab.lang.makeValidName(DistModes{i});
    tau_ads = AdsCCDFData.(dist_key).tau_ads;
    tau_ads = tau_ads(isfinite(tau_ads) & tau_ads > 0);

    if numel(tau_ads) < 3
        continue;
    end

    tau_ads = sort(tau_ads(:));
    N = numel(tau_ads);

    % CCDF: P(T > t)
    ccdf_y = (N:-1:1)' / N;

    h = plot(ax, tau_ads, ccdf_y, '-', ...
        'Color', Colors(i,:), ...
        'LineWidth', LineWidth_Base, ...
        'Marker', Markers{mod(i-1, numel(Markers))+1}, ...
        'MarkerSize', Marker_Size/10, ...
        'MarkerFaceColor', 'w', ...
        'MarkerEdgeColor', Colors(i,:));

    Legend_Handles = [Legend_Handles, h]; %#ok<AGROW>
    Legend_Labels{end+1} = strrep(DistModes{i}, '_', ' '); %#ok<AGROW>
end

legend(ax, Legend_Handles, Legend_Labels, 'Location', 'southwest', 'FontSize', 8, 'Box', 'off');
end

%% =========================================================================
function apply_axis_decor(ax, global_zero_mapped_val, isPhi0)

drawnow;
xticks_val = ax.XTick;
if ~ismember(global_zero_mapped_val, xticks_val)
    xticks_val = sort([global_zero_mapped_val, xticks_val]);
end
ax.XTick = xticks_val;

xticklabels_str = cell(1, length(xticks_val));
for k = 1:length(xticks_val)
    if xticks_val(k) <= global_zero_mapped_val * 1.1
        xticklabels_str{k} = '0';
    else
        xticklabels_str{k} = sprintf('%g', xticks_val(k));
    end
end
ax.XTickLabel = xticklabels_str;

plot(ax, ax.XLim, [0 0], 'k--', 'LineWidth', 1.2, 'HandleVisibility', 'off');
plot(ax, [1 1], ax.YLim, 'k:', 'LineWidth', 1.5, 'HandleVisibility', 'off');

if isPhi0
    ax.YLim = [0, 1.02];
    ax.YTick = 0:0.1:1.0;
else
    ax.YLim = [-0.2, 1.05];
    ax.YTick = -0.2:0.2:1.0;
end
end

%% =========================================================================
function save_one_figure(fig_handle, saveDir, figName)

safeFigName = regexprep(figName, '\s*\(.*?\)', '');
safeFigName = strrep(safeFigName, ' ', '_');
safeFigName = regexprep(safeFigName, '[\\/:*?"<>|()]', '');

savefig(fig_handle, fullfile(saveDir, [safeFigName, '.fig']));
try
    exportgraphics(fig_handle, fullfile(saveDir, [safeFigName, '.jpg']), 'Resolution', 300);
catch
    print(fig_handle, fullfile(saveDir, [safeFigName, '.jpg']), '-djpeg', '-r300');
end
end

%% =========================================================================
function save_axis_as_figure(ax_src, saveDir, figName)

fig_tmp = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 900 600]);
ax_new = copyobj(ax_src, fig_tmp);
set(ax_new, 'Position', get(groot, 'defaultAxesPosition'));

save_one_figure(fig_tmp, saveDir, figName);
close(fig_tmp);
end