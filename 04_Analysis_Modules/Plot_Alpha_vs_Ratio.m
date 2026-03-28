function Plot_Alpha_vs_Ratio()
% =========================================================================
% 功能：自动提取并绘制 输运不对称指数 (Transport Asymmetry Index)
% 高级特性：实现数据坍缩 (Data Collapse)。
% 物理映射：修正几何截面为 adR，使 X=1 极度敏感地对齐 \xi ~ 0.05 的绝对起飞点。
% =========================================================================
clc; clear; close all;

%% 1. 参数与路径配置
ControlVars = {'Tads0.0010_', 'adR1_', 'DS20_'}; 
DistModes   = {'PowerLaw_TI-2.5', 'PowerLaw_TI-1.9','PowerLaw_TI-1.5','PowerLaw_TI-1.1', 'PowerLaw_TI-0.9','PowerLaw_TI-0.5', ...
               'PowerLaw_TI0.5',  'PowerLaw_TI1.5',  'PowerLaw_TI2.5', ...
               'Exp', 'Uniform'};

Colors = lines(length(DistModes)); 
Marker_Size = 80;
LineWidth_Base = 2.5;

%% 2. 定位数据源
DataDir = fullfile(pwd, 'Simulation_Results');
Target_Dir = fullfile(pwd, 'analysis'); 
if ~exist(Target_Dir, 'dir') && exist(DataDir, 'dir')
    taskDirs = dir(fullfile(DataDir, 'Task_*'));
    if ~isempty(taskDirs)
        [~, idx] = max([taskDirs.datenum]);
        Target_Dir = fullfile(DataDir, taskDirs(idx).name);
    end
end
if ~exist(Target_Dir, 'dir'), error('找不到数据文件夹！'); end
fprintf('>>> 读取数据集目录: %s\n', Target_Dir);

all_items = dir(Target_Dir);
subfolders = all_items([all_items.isdir] & ~ismember({all_items.name}, {'.','..'}));

%% 3. 初始化画图窗口
fig = figure('Name', 'Transport_Asymmetry_MasterCurve_Sensitive', 'Position', [150, 150, 900, 600], 'Color', 'w');
hold on; box on;
set(gca, 'FontSize', 16, 'LineWidth', 1.5, 'TickDir', 'in', 'XScale', 'log');
Legend_Handles = [];
Legend_Labels  = {};

%% 4. 核心计算与提取循环
global_zero_mapped_val = 1e-8; 

for i = 1:length(DistModes)
    current_dist = DistModes{i};
    fprintf('[+] 正在分析分布模式: %s\n', current_dist);
    
    match_mask = true(1, length(subfolders));
    for c = 1:length(ControlVars)
        match_mask = match_mask & contains({subfolders.name}, ControlVars{c}); 
    end
    match_mask = match_mask & contains({subfolders.name}, current_dist);
    matching_folders = subfolders(match_mask);
    
    if isempty(matching_folders), continue; end
    
    Ratio_DataMap = containers.Map('KeyType', 'double', 'ValueType', 'any');
    
    for f = 1:length(matching_folders)
        folder_name = matching_folders(f).name;
        
        tokens_n = regexp(folder_name, 'ratio_([0-9\.eE\-]+)k', 'tokens');
        if isempty(tokens_n), continue; end
        n_val = str2double(tokens_n{1}{1});
        
        tokens_jf = regexp(folder_name, 'jf([0-9\.eE\-]+)_', 'tokens');
        tokens_adR = regexp(folder_name, 'adR([0-9\.eE\-]+)_', 'tokens');
        tokens_ds = regexp(folder_name, 'DS([0-9\.eE\-]+)_', 'tokens');
        tokens_Ts = regexp(folder_name, 'Ts([0-9\.eE\-]+)_', 'tokens');
        tokens_Tads = regexp(folder_name, 'Tads([0-9\.eE\-]+)_', 'tokens');
        
        if ~isempty(tokens_jf), jf_val = str2double(tokens_jf{1}{1}); else, jf_val = 1e8; end
        if ~isempty(tokens_adR), adR_val = str2double(tokens_adR{1}{1}); else, adR_val = 1.0; end
        if ~isempty(tokens_ds), ds_val = str2double(tokens_ds{1}{1}); else, ds_val = 20.0; end
        if ~isempty(tokens_Ts), Ts_val = str2double(tokens_Ts{1}{1}); else, Ts_val = 0.02; end
        if ~isempty(tokens_Tads), Tads_val = str2double(tokens_Tads{1}{1}); else, Tads_val = 0.0010; end
        
        % [C] 核心推导：更加敏感的起点可见阈值 n_vis
        D_val = 1e-10; % 理论扩散系数 m^2/s
        k_nm = sqrt(2 * D_val / jf_val) * 1e9; % 热步长 (nm)
        
        % 【修改点】：去掉系数 2，以半径(adR)作为对称性破缺的最敏感标尺
        n_geo = (adR_val * k_nm) / (ds_val^2);
        
        t_free = (ds_val * 1e-9)^2 / (4 * D_val);
        M_eff = Ts_val / (t_free + Tads_val);
        
        % 高敏感度的宏观相变起点阈值
        n_vis = n_geo / sqrt(M_eff);
        
        if n_vis > 0
            scaled_X = n_val / n_vis;
        else
            scaled_X = n_val;
        end
        
        if scaled_X > 0
            scaled_X = str2double(sprintf('%.5g', scaled_X));
        end
        
        folder_path = fullfile(Target_Dir, folder_name);
        mat_files = dir(fullfile(folder_path, '*.mat'));
        
        dx_temp = [];
        for rep_f = 1:length(mat_files)
            try
                data = load(fullfile(folder_path, mat_files(rep_f).name), 'positionlist');
                if isfield(data, 'positionlist') && size(data.positionlist, 2) >= 3
                    pos = data.positionlist;
                    frames = double(pos(:, 3));
                    [~, ~, idx] = unique(frames);
                    mean_X = accumarray(idx, pos(:, 1)) ./ accumarray(idx, 1);
                    dx_now = mean_X(2:end) - mean_X(1:end-1); 
                    dx_temp = [dx_temp; dx_now]; %#ok<AGROW>
                end
            catch
                continue;
            end
        end
        
        if isKey(Ratio_DataMap, scaled_X)
            Ratio_DataMap(scaled_X) = [Ratio_DataMap(scaled_X); dx_temp];
        else
            Ratio_DataMap(scaled_X) = dx_temp;
        end
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
    
    plot_ratios = [];
    plot_alphas = [];
    
    for r = 1:length(unique_ratios)
        scaled_X = unique_ratios(r);
        dx_v = Ratio_DataMap(scaled_X);
        
        if length(dx_v) < 10, continue; end 
        
        dx_R = dx_v(dx_v > 0);
        dx_L = dx_v(dx_v < 0);
        
        if isempty(dx_R), M_R = 0; else, M_R = mean(dx_R); end
        if isempty(dx_L), M_L = 0; else, M_L = abs(mean(dx_L)); end 
        
        if M_R == 0 && M_L == 0
            metric_val = 0; 
        else
            metric_val = (M_R - M_L) / max(M_R, M_L);
        end
        
        %metric_val = max(0, metric_val);

        if ~isnan(metric_val)
            if scaled_X == 0
                plot_ratios(end+1) = zero_mapped_val; %#ok<AGROW>
            else
                plot_ratios(end+1) = scaled_X; %#ok<AGROW>
            end
            plot_alphas(end+1) = metric_val; %#ok<AGROW>
        end
    end
    
    if ~isempty(plot_ratios)        
        this_color = Colors(mod(i-1, size(Colors, 1)) + 1, :);
        Markers = {'o', 's', 'd', '^', 'v', 'p', 'h', '*'};
        
        h_line = plot(plot_ratios, plot_alphas, ...
             '-', 'Marker', Markers{mod(i-1, 8)+1}, ...
             'Color', this_color, ...
             'LineWidth', LineWidth_Base, 'MarkerSize', Marker_Size/10, ...
             'MarkerFaceColor', 'w', 'MarkerEdgeColor', this_color);
         
        Legend_Handles = [Legend_Handles, h_line]; %#ok<AGROW>
        Legend_Labels{end+1}  = strrep(current_dist, '_', ' '); %#ok<AGROW>
    end
end

%% 5. 图像美化与修饰
xlabel('Normalized Driving Force \it{n / n_{vis}}', 'FontSize', 18, 'FontWeight', 'bold');
ylabel('Transport Asymmetry Index \xi', 'FontSize', 18, 'FontWeight', 'bold');

title(''); 
ax = gca;
ax.XLim = [global_zero_mapped_val / 2, max(plot_ratios)*2]; 
ax.YLim = [-0.1, 1.1]; 
ax.YTick = 0 : 0.2 : 1.0; 

ax.XTickMode = 'auto';
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

% 1. 0 轴底噪基准线
plot(ax.XLim, [0 0], 'k--', 'LineWidth', 1.5, 'HandleVisibility', 'off');
% 2. X=1 的相变敏感起飞锚点基准线
plot([1 1], [-0.1 1.1], 'k:', 'LineWidth', 2, 'HandleVisibility', 'off');

legend(Legend_Handles, Legend_Labels, 'Location', 'northwest', 'FontSize', 12, 'Box', 'off');
grid on;
set(gca, 'GridAlpha', 0.15);

fprintf('>>> 绘图完成！\n');
saveDir = fullfile(pwd, 'Saved_Figures');
if ~exist(saveDir, 'dir'), mkdir(saveDir); end
savefig(fig, fullfile(saveDir, 'Transport_Asymmetry_MasterCurve_Sensitive.fig'));
exportgraphics(fig, fullfile(saveDir, 'Transport_Asymmetry_MasterCurve_Sensitive.jpg'), 'Resolution', 300);
end