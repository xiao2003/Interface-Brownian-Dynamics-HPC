function Plot_Alpha_vs_Ratio_AllMetrics_SavePDF()
% =========================================================================
% 4-panel analysis:
%   (a) Conditional Asymmetry
%   (b) Central-Peak / Stagnation Fraction
%   (c) Adsorption-Time PDF (true density)
%   (d) Effective Transport Asymmetry
%
% Key updates:
%   1) Panel 3 uses true PDF: counts / (N * bin_width)
%   2) Panel 3 style is unified with the other panels
%   3) Legend appears only in panel 1 (upper-left)
%   4) No legend(tiledlayout, ...) call
% =========================================================================

clc;
clear;
close all;

%% ========================================================================
% 1. User settings
% =========================================================================
ControlVars = {'Tads0.0010_', 'adR1_', 'DS20_'};

DistModes = { ...
    'PowerLaw_TI-2.5', ...
    'PowerLaw_TI-1.9', ...
    'PowerLaw_TI-1.5', ...
    'PowerLaw_TI-1.1', ...
    'PowerLaw_TI-0.9', ...
    'PowerLaw_TI-0.5', ...
    'PowerLaw_TI0.5', ...
    'PowerLaw_TI1.5', ...
    'PowerLaw_TI2.5', ...
    'Exp', ...
    'Uniform'};

Colors = lines(numel(DistModes));
Marker_Size    = 70;
LineWidth_Base = 2.4;

DeltaFactor   = 1.0;
MinTotalCount = 1;
D_val         = 1e-10;

% ---- Panel 3 PDF settings ----
PDF_GridN       = 50;      % recommended: 40-60
PDF_Q_Low       = 0.001;
PDF_Q_High      = 0.999;
UseRelativeTime = true;    % recommended: true
PDF_MinPositive = 1e-8;

%% ========================================================================
% 2. Locate data source
% =========================================================================
baseResultDir = fullfile(pwd, 'Simulation_Results');
Target_Dir    = fullfile(pwd, 'analysis');

if ~exist(Target_Dir, 'dir') && exist(baseResultDir, 'dir')
    taskDirs = dir(fullfile(baseResultDir, 'Task_*'));
    if ~isempty(taskDirs)
        [~, idx] = max([taskDirs.datenum]);
        Target_Dir = fullfile(baseResultDir, taskDirs(idx).name);
        fprintf('>>> analysis folder not found. Redirected to latest Task_*: %s\n', taskDirs(idx).name);
    end
end

if ~exist(Target_Dir, 'dir')
    error('Cannot find data folder. Expected analysis or Simulation_Results/Task_*');
end

fprintf('>>> Reading dataset directory: %s\n', Target_Dir);

all_items  = dir(Target_Dir);
subfolders = all_items([all_items.isdir] & ~ismember({all_items.name}, {'.','..'}));

%% ========================================================================
% 3. Initialize data containers
% =========================================================================
MetricNames = {'xi_cond', 'phi0', 'xi_eff'};

AllMetricData = struct();
AdsPDFData    = struct();

for m = 1:numel(MetricNames)
    metric_name = MetricNames{m};
    for i = 1:numel(DistModes)
        dist_name = matlab.lang.makeValidName(DistModes{i});
        AllMetricData.(metric_name).(dist_name).X = [];
        AllMetricData.(metric_name).(dist_name).Y = [];
    end
end

for i = 1:numel(DistModes)
    dist_name = matlab.lang.makeValidName(DistModes{i});
    AdsPDFData.(dist_name).tau_ads = [];
end

global_zero_mapped_val = 1e-8;

%% ========================================================================
% 4. Core extraction loop
% =========================================================================
for i = 1:numel(DistModes)
    current_dist = DistModes{i};
    fprintf('[+] Processing distribution mode: %s\n', current_dist);

    match_mask = true(1, numel(subfolders));
    for c = 1:numel(ControlVars)
        match_mask = match_mask & contains({subfolders.name}, ControlVars{c});
    end
    match_mask = match_mask & contains({subfolders.name}, current_dist);
    matching_folders = subfolders(match_mask);

    if isempty(matching_folders)
        fprintf('    -> No matching folders.\n');
        continue;
    end

    Ratio_DataMap = containers.Map('KeyType', 'double', 'ValueType', 'any');
    Ads_DataMap   = containers.Map('KeyType', 'double', 'ValueType', 'any');

    for f = 1:numel(matching_folders)
        folder_name = matching_folders(f).name;
        folder_path = fullfile(Target_Dir, folder_name);

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

        for rep_f = 1:numel(mat_files)
            file_path = fullfile(folder_path, mat_files(rep_f).name);

            try
                data = load(file_path);
            catch
                continue;
            end

            if isfield(data, 'positionlist') && size(data.positionlist, 2) >= 3
                pos = data.positionlist;
                frames = double(pos(:,3));

                [~, ~, idxFrame] = unique(frames);
                mean_X = accumarray(idxFrame, pos(:,1)) ./ accumarray(idxFrame, 1);

                if numel(mean_X) >= 2
                    dx_now = mean_X(2:end) - mean_X(1:end-1);
                    dx_temp = [dx_temp; dx_now(:)]; %#ok<AGROW>
                end
            end

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

    for r = 1:numel(unique_ratios)
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

    % choose tau_ads sample closest to n/n_vis ~= 1 for panel 3
    ads_keys = cell2mat(keys(Ads_DataMap));
    ads_keys = ads_keys(isfinite(ads_keys) & ads_keys > 0);

    if ~isempty(ads_keys)
        [~, idx_best] = min(abs(log10(ads_keys) - log10(1)));
        best_key = ads_keys(idx_best);
        tau_ads = Ads_DataMap(best_key);
        tau_ads = tau_ads(isfinite(tau_ads) & tau_ads > 0);
        AdsPDFData.(dist_key).tau_ads = tau_ads;
    end
end

%% ========================================================================
% 5. Build save folder
% =========================================================================
ctrl_str = strjoin(ControlVars, '_');
inv_str  = 'AllMetrics_AdsPDF_Clean';
folderName = sprintf('[%s][%s]', ctrl_str, inv_str);

if length(folderName) > 150
    folderName = [folderName(1:145), '...]'];
end
folderName = regexprep(folderName, '[\\/:*?"<>|]', '_');

saveDir = fullfile(pwd, 'Saved_Figures', folderName);
if ~exist(saveDir, 'dir')
    mkdir(saveDir);
end

%% ========================================================================
% 6. Draw combined panel
% =========================================================================
fig_combo = figure('Name', 'Combined_Panel', ...
                   'Position', [40, 20, 2200, 1300], ...
                   'Color', 'w');

tlo = tiledlayout(2,2, 'TileSpacing', 'compact', 'Padding', 'compact');

% ---- (a) Conditional Asymmetry ----
ax1 = nexttile(tlo, 1);
hold(ax1, 'on'); box(ax1, 'on');
[legendHandles, legendLabels] = plot_mastercurve(ax1, AllMetricData.xi_cond, DistModes, Colors, Marker_Size, LineWidth_Base, true);
set(ax1, 'XScale', 'log', 'FontSize', 16, 'LineWidth', 1.6, 'TickDir', 'in');
xlabel(ax1, 'Normalized Driving Force  n / n_{vis}', 'FontSize', 18, 'FontWeight', 'bold');
ylabel(ax1, '\xi_{cond}', 'FontSize', 18, 'FontWeight', 'bold');
title(ax1, 'Conditional Asymmetry', 'FontSize', 18, 'FontWeight', 'bold');
apply_axis_decor(ax1, global_zero_mapped_val, false);

% only panel-1 legend
legend(ax1, legendHandles, legendLabels, ...
    'Location', 'northwest', ...
    'FontSize', 10, ...
    'Interpreter', 'none', ...
    'Box', 'off');

% ---- (b) Stagnation Fraction ----
ax2 = nexttile(tlo, 2);
hold(ax2, 'on'); box(ax2, 'on');
plot_mastercurve(ax2, AllMetricData.phi0, DistModes, Colors, Marker_Size, LineWidth_Base, false);
set(ax2, 'XScale', 'log', 'FontSize', 16, 'LineWidth', 1.6, 'TickDir', 'in');
xlabel(ax2, 'Normalized Driving Force  n / n_{vis}', 'FontSize', 18, 'FontWeight', 'bold');
ylabel(ax2, '\phi_0', 'FontSize', 18, 'FontWeight', 'bold');
title(ax2, 'Central-Peak / Stagnation Fraction', 'FontSize', 18, 'FontWeight', 'bold');
apply_axis_decor(ax2, global_zero_mapped_val, true);

% ---- (c) Adsorption-Time PDF ----
ax3 = nexttile(tlo, 3);
hold(ax3, 'on'); box(ax3, 'on');
plot_adsorption_pdf_true(ax3, AdsPDFData, DistModes, Colors, Marker_Size, LineWidth_Base, ...
    PDF_GridN, PDF_Q_Low, PDF_Q_High, UseRelativeTime, PDF_MinPositive);
set(ax3, 'XScale', 'log', 'YScale', 'log', 'FontSize', 16, 'LineWidth', 1.6, 'TickDir', 'in');

if UseRelativeTime
    xlabel(ax3, '\tau_{ads} / \tau_{50}', 'FontSize', 18, 'FontWeight', 'bold');
else
    xlabel(ax3, 'Adsorption Time  \tau_{ads} (s)', 'FontSize', 18, 'FontWeight', 'bold');
end

ylabel(ax3, 'PDF', 'FontSize', 18, 'FontWeight', 'bold');
title(ax3, 'Adsorption-Time Probability Density', 'FontSize', 18, 'FontWeight', 'bold');
grid(ax3, 'on');

% ---- (d) Effective Transport Asymmetry ----
ax4 = nexttile(tlo, 4);
hold(ax4, 'on'); box(ax4, 'on');
plot_mastercurve(ax4, AllMetricData.xi_eff, DistModes, Colors, Marker_Size, LineWidth_Base, false);
set(ax4, 'XScale', 'log', 'FontSize', 16, 'LineWidth', 1.6, 'TickDir', 'in');
xlabel(ax4, 'Normalized Driving Force  n / n_{vis}', 'FontSize', 18, 'FontWeight', 'bold');
ylabel(ax4, '\Xi_{eff}', 'FontSize', 18, 'FontWeight', 'bold');
title(ax4, 'Effective Transport Asymmetry', 'FontSize', 18, 'FontWeight', 'bold');
apply_axis_decor(ax4, global_zero_mapped_val, false);

%% ========================================================================
% 7. Save outputs
% =========================================================================
save_one_figure(fig_combo, saveDir, 'Combined_Panel');
save_axis_as_figure(ax1, saveDir, 'Conditional_Asymmetry');
save_axis_as_figure(ax2, saveDir, 'Central_Peak_Stagnation');
save_axis_as_figure(ax3, saveDir, 'Adsorption_Time_PDF');
save_axis_as_figure(ax4, saveDir, 'Effective_Transport_Asymmetry');

save(fullfile(saveDir, 'Raw_Metrics.mat'), ...
    'AllMetricData', 'AdsPDFData', 'ControlVars', 'DistModes');

fprintf('>>> All figures saved to: %s\n', saveDir);

end

%% ========================================================================
function [xi_cond, phi0, xi_eff] = compute_main_metrics(dx_v, delta_nm)

dx_v = dx_v(:);
dx_v = dx_v(isfinite(dx_v));

dx_R = dx_v(dx_v > 0);
dx_L = dx_v(dx_v < 0);

if isempty(dx_R)
    M_R = 0;
else
    M_R = mean(dx_R);
end

if isempty(dx_L)
    M_L = 0;
else
    M_L = abs(mean(dx_L));
end

if M_R == 0 && M_L == 0
    xi_cond = 0;
else
    xi_cond = (M_R - M_L) / max(M_R, M_L);
end

phi0 = mean(abs(dx_v) <= delta_nm);

dx_mov = dx_v(abs(dx_v) > delta_nm);
if isempty(dx_mov)
    xi_move = 0;
else
    dx_Rm = dx_mov(dx_mov > 0);
    dx_Lm = dx_mov(dx_mov < 0);

    if isempty(dx_Rm)
        M_Rm = 0;
    else
        M_Rm = mean(dx_Rm);
    end

    if isempty(dx_Lm)
        M_Lm = 0;
    else
        M_Lm = abs(mean(dx_Lm));
    end

    if M_Rm == 0 && M_Lm == 0
        xi_move = 0;
    else
        xi_move = (M_Rm - M_Lm) / max(M_Rm, M_Lm);
    end
end

xi_eff = (1 - phi0) * xi_move;

end

%% ========================================================================
function [handles, labels] = plot_mastercurve(ax, MetricStruct, DistModes, Colors, Marker_Size, LineWidth_Base, returnHandles)

if nargin < 7
    returnHandles = false;
end

Markers = {'o','s','d','^','v','p','h','*','>','<','x'};
handles = gobjects(0);
labels  = {};

maxX_local = 1;
global_zero_tick = inf;

for i = 1:numel(DistModes)
    dist_key = matlab.lang.makeValidName(DistModes{i});
    X = MetricStruct.(dist_key).X;
    Y = MetricStruct.(dist_key).Y;

    if isempty(X)
        continue;
    end

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
        'MarkerIndices', 1:2:max(1, numel(Xuniq)), ...
        'MarkerSize', Marker_Size/10, ...
        'MarkerFaceColor', 'w', ...
        'MarkerEdgeColor', Colors(i,:));

    if returnHandles
        handles(end+1) = h; %#ok<AGROW>
        labels{end+1} = strrep(DistModes{i}, '_', ' '); %#ok<AGROW>
    end
end

if isfinite(global_zero_tick)
    ax.XLim = [global_zero_tick/2, maxX_local*2];
end

grid(ax, 'on');
set(ax, 'GridAlpha', 0.15);

end

%% ========================================================================
function plot_adsorption_pdf_true(ax, AdsPDFData, DistModes, Colors, Marker_Size, LineWidth_Base, ...
    GridN, qLow, qHigh, UseRelativeTime, PDF_MinPositive)

Markers = {'o','s','d','^','v','p','h','*','>','<','x'};

all_min = [];
all_max = [];

% determine global x-range
for i = 1:numel(DistModes)
    dist_key = matlab.lang.makeValidName(DistModes{i});
    tau_ads = AdsPDFData.(dist_key).tau_ads;
    tau_ads = tau_ads(isfinite(tau_ads) & tau_ads > 0);

    if isempty(tau_ads)
        continue;
    end

    if UseRelativeTime
        t50 = median(tau_ads);
        if ~(isfinite(t50) && t50 > 0)
            continue;
        end
        tau_ads = tau_ads / t50;
    end

    lo = quantile(tau_ads, qLow);
    hi = quantile(tau_ads, qHigh);

    if isfinite(lo) && isfinite(hi) && hi > lo && lo > 0
        all_min(end+1) = lo; %#ok<AGROW>
        all_max(end+1) = hi; %#ok<AGROW>
    end
end

if isempty(all_min)
    text(ax, 0.5, 0.5, 'No valid adsorption-time data', ...
        'Units', 'normalized', ...
        'HorizontalAlignment', 'center', ...
        'FontSize', 14, ...
        'Color', 'r');
    return;
end

xMin = min(all_min);
xMax = max(all_max);

edges   = logspace(log10(xMin), log10(xMax), GridN + 1);
centers = sqrt(edges(1:end-1) .* edges(2:end));
widths  = diff(edges);

min_pdf = inf;
max_pdf = 0;

for i = 1:numel(DistModes)
    dist_key = matlab.lang.makeValidName(DistModes{i});
    tau_ads = AdsPDFData.(dist_key).tau_ads;
    tau_ads = tau_ads(isfinite(tau_ads) & tau_ads > 0);

    if isempty(tau_ads)
        continue;
    end

    if UseRelativeTime
        t50 = median(tau_ads);
        if ~(isfinite(t50) && t50 > 0)
            continue;
        end
        tau_ads = tau_ads / t50;
    end

    counts = histcounts(tau_ads, edges);
    if sum(counts) == 0
        continue;
    end

    % true PDF
    pdf = counts ./ (sum(counts) .* widths);

    valid = isfinite(pdf) & (pdf > PDF_MinPositive);
    if nnz(valid) < 3
        continue;
    end

    min_pdf = min(min_pdf, min(pdf(valid)));
    max_pdf = max(max_pdf, max(pdf(valid)));

    idx_valid = find(valid);
    if numel(idx_valid) > 12
        idx_show = idx_valid(1:2:end);
    else
        idx_show = idx_valid;
    end

    local_centers = centers(valid);
    local_pdf     = pdf(valid);

    marker_idx = idx_show - idx_valid(1) + 1;
    marker_idx = marker_idx(marker_idx >= 1 & marker_idx <= numel(local_centers));

    plot(ax, local_centers, local_pdf, '-', ...
        'Color', Colors(i,:), ...
        'LineWidth', LineWidth_Base, ...
        'Marker', Markers{mod(i-1, numel(Markers))+1}, ...
        'MarkerIndices', marker_idx, ...
        'MarkerSize', Marker_Size/10, ...
        'MarkerFaceColor', 'w', ...
        'MarkerEdgeColor', Colors(i,:));
end

if isfinite(min_pdf) && max_pdf > 0
    ylim(ax, [max(PDF_MinPositive, min_pdf/2), max_pdf*2]);
end

xlim(ax, [xMin, xMax]);

end

%% ========================================================================
function apply_axis_decor(ax, global_zero_mapped_val, isPhi0)

drawnow;
xticks_val = ax.XTick;

if ~ismember(global_zero_mapped_val, xticks_val)
    xticks_val = sort([global_zero_mapped_val, xticks_val]);
end
ax.XTick = xticks_val;

xticklabels_str = cell(1, numel(xticks_val));
for k = 1:numel(xticks_val)
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

%% ========================================================================
function save_one_figure(fig_handle, saveDir, figName)

safeFigName = regexprep(figName, '\s*\(.*?\)', '');
safeFigName = strrep(safeFigName, ' ', '_');
safeFigName = regexprep(safeFigName, '[\\/:*?"<>|()]', '');

savefig(fig_handle, fullfile(saveDir, [safeFigName, '.fig']));
try
    exportgraphics(fig_handle, fullfile(saveDir, [safeFigName, '.jpg']), 'Resolution', 600);
    exportgraphics(fig_handle, fullfile(saveDir, [safeFigName, '.pdf']), 'ContentType', 'vector');
catch
    print(fig_handle, fullfile(saveDir, [safeFigName, '.jpg']), '-djpeg', '-r600');
end

end

%% ========================================================================
function save_axis_as_figure(ax_src, saveDir, figName)

fig_tmp = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1100 800]);
ax_new = copyobj(ax_src, fig_tmp);
set(ax_new, 'Position', get(groot, 'defaultAxesPosition'));

save_one_figure(fig_tmp, saveDir, figName);
close(fig_tmp);

end