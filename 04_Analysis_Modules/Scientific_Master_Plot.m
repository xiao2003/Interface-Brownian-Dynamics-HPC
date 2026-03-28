function Scientific_Master_Plot()
    % =====================================================================
    % IBD-HPC 全能单分子分析控制台 (顶刊视觉 + 全自动自适应版)
    % 完美对标论文级 1D 散点 PDF、2D 等高线漂移、跳跃长度与 MSD 动力学
    % =====================================================================
    clc; clear; close all;

    % ---------------------------------------------------------------------
    % [1. 模块生成开关] (true为开启，false为关闭)
    % ---------------------------------------------------------------------
    Enable_1D_PDF      = true;  % [图1] X/Y位移1D概率密度图 (半对数纯散点)
    Enable_2D_Contour  = true;  % [图2] XY位移2D等高线重叠图 (揭示Vx/Vy各向异性)
    Enable_JumpLength  = true;  % [图3] 跳跃长度 (DL) 分布图
    Enable_MSD         = true;  % [图4] 均方位移 (MSD) 曲线与扩散系数拟合

    % ---------------------------------------------------------------------
    % [2. 科学正交对比过滤]
    % ---------------------------------------------------------------------
    ControlVars     = {'PowerLaw', 'TI2.5','Vx_0'}; % 必须同时包含的通用参数
    InvestigateVars = {'Tads0.01', 'Tads0.05', 'Tads0.20', 'Tads0.50'}; % 你要对比的变量

    % ---------------------------------------------------------------------
    % [3. 全自动自适应与离散化参数]
    % ---------------------------------------------------------------------
    LagSteps        = 1;        % 计算位移的步长跨度
    Dt_Default      = 0.02;     % 默认时间步长(s)。若文件含 p 将自动覆盖
    AutoPrctile     = 99.8;     % 【核心】自适应剔除 万分之二 的极端飞点
    
    Bins_1D         = 120;      % 1D 直方图分箱数
    Bins_2D         = 80;       % 2D 等高线网格数
    ContourLevels   = 4;        % 2D 等高线绘制圈数
    Max_MSD_Frames  = 500;      % MSD 最大计算帧数 
    LinearT_Fit     = 5;        % MSD 线性拟合前 N 秒

    % ---------------------------------------------------------------------
    % [4. 论文级视觉规范 (对标参考图)]
    % ---------------------------------------------------------------------
    FontSize_Axis   = 16;       % 坐标轴字号
    FontSize_Legend = 12;       % 图例字号
    LineWidth_Base  = 1.5;      % 边框粗细
    Marker_Size     = 50;       % 散点极其饱满的大小 (对标 Nature 风格)
    Alpha_Base      = 0.8;      % 散点透明度 (透出底层的点)

    % 提取自高分论文的经典调色盘
    Colors = [
        0.00, 0.45, 0.74;  % 深蓝
        0.85, 0.33, 0.10;  % 砖红
        0.93, 0.69, 0.13;  % 亮黄
        0.49, 0.18, 0.56;  % 绛紫
        0.47, 0.67, 0.19;  % 草绿
        0.30, 0.75, 0.93   % 浅蓝
    ];
    %% ====================================================================

    %% ================== 核心执行区 (勿动) ==================
    fprintf('>>> 启动 HPC 顶刊分析引擎...\n');
    all_items = dir(pwd);
    subfolders = all_items([all_items.isdir] & ~ismember({all_items.name}, {'.', '..'}));

    GroupData = struct();
    valid_count = 0;
    global_max_dx = 0; 
    global_max_dl = 0;
    Dt_Actual = Dt_Default; 

    %% 【第一阶段：数据系综池化与极速读取】
    for i = 1:length(InvestigateVars)
        current_var = InvestigateVars{i};
        
        match_mask = true(1, length(subfolders));
        for c = 1:length(ControlVars), match_mask = match_mask & contains({subfolders.name}, ControlVars{c}); end
        match_mask = match_mask & contains({subfolders.name}, current_var);
        matching_folders = subfolders(match_mask);
        
        if isempty(matching_folders), continue; end
        valid_count = valid_count + 1;
        
        dx_merged = []; dy_merged = []; dl_merged = [];
        msd_sum = zeros(1, Max_MSD_Frames); msd_count = zeros(1, Max_MSD_Frames);
        
        fprintf('[+] 融合特征系综: %s (包含 %d 组 Rep)...\n', current_var, length(matching_folders));

        for f = 1:length(matching_folders)
            folder_path = fullfile(pwd, matching_folders(f).name);
            mat_files = dir(fullfile(folder_path, '*.mat'));

            for rep = 1:length(mat_files)
                try
                    data = load(fullfile(folder_path, mat_files(rep).name), 'positionlist', 'p');
                    if isfield(data, 'p'), Dt_Actual = data.p(1); end 
                    
                    if isfield(data, 'positionlist') && size(data.positionlist, 2) >= 2
                        X = data.positionlist(:, 1); Y = data.positionlist(:, 2);
                        
                        if length(X) > LagSteps
                            dx_now = X(1+LagSteps:end) - X(1:end-LagSteps);
                            dy_now = Y(1+LagSteps:end) - Y(1:end-LagSteps);
                            dx_merged = [dx_merged, reshape(dx_now, 1, [])]; %#ok<AGROW>
                            dy_merged = [dy_merged, reshape(dy_now, 1, [])]; %#ok<AGROW>
                            dl_merged = [dl_merged, reshape(sqrt(dx_now.^2 + dy_now.^2), 1, [])]; %#ok<AGROW>
                        end
                        
                        if Enable_MSD
                            frames_to_calc = min(Max_MSD_Frames, length(X)-1);
                            for step = 1:frames_to_calc
                                sq_disp = (X(1+step:end) - X(1:end-step)).^2 + (Y(1+step:end) - Y(1:end-step)).^2;
                                valid_sq = sq_disp(~isnan(sq_disp) & ~isinf(sq_disp));
                                msd_sum(step) = msd_sum(step) + sum(valid_sq);
                                msd_count(step) = msd_count(step) + length(valid_sq);
                            end
                        end
                    end
                catch
                    continue;
                end
            end
        end

        valid_mask = ~isnan(dx_merged) & ~isinf(dx_merged);
        GroupData(valid_count).name = strrep(current_var, '_', ' ');
        GroupData(valid_count).dx = dx_merged(valid_mask);
        GroupData(valid_count).dy = dy_merged(valid_mask);
        GroupData(valid_count).dl = dl_merged(valid_mask);
        
        if Enable_MSD
            GroupData(valid_count).msd = msd_sum ./ max(msd_count, 1); 
        end
        
        % 计算自适应物理边界
        if any(valid_mask)
            p_dx = prctile(abs(GroupData(valid_count).dx), AutoPrctile);
            p_dy = prctile(abs(GroupData(valid_count).dy), AutoPrctile);
            global_max_dx = max([global_max_dx, p_dx, p_dy]);
            global_max_dl = max(global_max_dl, prctile(GroupData(valid_count).dl, AutoPrctile));
        end
    end

    if valid_count == 0, error('未提取到任何数据，请检查变量词。'); end

    % 【终极自适应】15% 留白，凑整 10 nm，完美包裹 99.8% 核心物理现象
    limit_dx = ceil((max(global_max_dx, 50) * 1.15) / 10) * 10;
    limit_dl = ceil((max(global_max_dl, 50) * 1.15) / 10) * 10;
    XLimRange = [-limit_dx, limit_dx];
    fprintf('>>> 物理自适应边界已锁定: 位移极限 \x00B1%g nm | 步长极限 %g nm\n', limit_dx, limit_dl);

    %% 【第二阶段：多重画布分发与渲染】
    
    % -----------------------------------------------------------------
    % [图 1] 1D 位移散点图 (完美对标参考图风格)
    % -----------------------------------------------------------------
    if Enable_1D_PDF
        figure('Name', '1D Displacement PDF', 'Position', [100, 100, 650, 500]);
        hold on; box on; 
        set(gca, 'YScale', 'log', 'FontSize', FontSize_Axis, 'LineWidth', LineWidth_Base, ...
            'TickDir', 'in', 'XMinorTick', 'on', 'YMinorTick', 'on'); 
        
        LegendEntries1 = {};
        for i = 1:valid_count
            % 截断数据以适应网格
            dx_v = GroupData(i).dx(GroupData(i).dx >= XLimRange(1) & GroupData(i).dx <= XLimRange(2));
            edges = linspace(XLimRange(1), XLimRange(2), Bins_1D+1); 
            centers = edges(1:end-1) + diff(edges)/2;
            
            % PDF 归一化
            pdf = histcounts(dx_v, edges) / (length(dx_v) * (edges(2)-edges(1)));
            pidx = pdf > 0; 
            c_idx = mod(i-1, size(Colors, 1)) + 1;
            
            % 核心画法：抛弃连线，使用高通透大圆点
            scatter(centers(pidx), pdf(pidx), Marker_Size, Colors(c_idx,:), 'filled', ...
                'MarkerFaceAlpha', Alpha_Base, 'MarkerEdgeColor', 'none');
                
            LegendEntries1{i} = GroupData(i).name;
        end
        legend(LegendEntries1, 'Location', 'northeast', 'FontSize', FontSize_Legend, 'Box', 'off');
        xlabel('dx (nm)', 'FontWeight', 'bold'); ylabel('G', 'FontWeight', 'bold');
        xlim(XLimRange); ylim([1e-5, 2]); % 预留顶部空间给 0 点尖峰
    end

    % -----------------------------------------------------------------
    % [图 2] 2D XY 位移等高线重叠图
    % -----------------------------------------------------------------
    if Enable_2D_Contour
        figure('Name', '2D Contour Overlap', 'Position', [150, 150, 600, 600]);
        hold on; box on; 
        set(gca, 'FontSize', FontSize_Axis, 'LineWidth', LineWidth_Base, 'TickDir', 'in');
        
        LegendEntries2 = {}; Handles2 = [];
        for i = 1:valid_count
            dx_v = GroupData(i).dx; dy_v = GroupData(i).dy;
            v_idx = (dx_v >= XLimRange(1)) & (dx_v <= XLimRange(2)) & (dy_v >= XLimRange(1)) & (dy_v <= XLimRange(2));
            edges = linspace(XLimRange(1), XLimRange(2), Bins_2D+1); 
            centers = edges(1:end-1) + diff(edges)/2;
            
            [N, ~, ~] = histcounts2(dx_v(v_idx), dy_v(v_idx), edges, edges);
            N_smooth = conv2(N, [1 2 1; 2 4 2; 1 2 1]/16, 'same');
            PDF_2D = N_smooth / sum(N_smooth(:));
            
            c_idx = mod(i-1, size(Colors, 1)) + 1; current_color = Colors(c_idx, :);
            contour(centers, centers, PDF_2D', ContourLevels, 'LineColor', current_color, 'LineWidth', 2.0);
            
            LegendEntries2{i} = GroupData(i).name;
            Handles2 = [Handles2, plot(NaN, NaN, '-', 'Color', current_color, 'LineWidth', 3)]; %#ok<AGROW>
        end
        xline(0, 'k--', 'Alpha', 0.3, 'LineWidth', LineWidth_Base); yline(0, 'k--', 'Alpha', 0.3, 'LineWidth', LineWidth_Base);
        legend(Handles2, LegendEntries2, 'Location', 'northeast', 'FontSize', FontSize_Legend, 'Box', 'off');
        xlabel('dx (nm)', 'FontWeight', 'bold'); ylabel('dy (nm)', 'FontWeight', 'bold');
        axis equal; xlim(XLimRange); ylim(XLimRange);
    end

    % -----------------------------------------------------------------
    % [图 3] 跳跃长度 (Jump Length DL) 分布图
    % -----------------------------------------------------------------
    if Enable_JumpLength
        figure('Name', 'Jump Length Distribution', 'Position', [200, 200, 650, 500]);
        hold on; box on; 
        set(gca, 'YScale', 'log', 'FontSize', FontSize_Axis, 'LineWidth', LineWidth_Base, ...
            'TickDir', 'in', 'XMinorTick', 'on', 'YMinorTick', 'on'); 
            
        LegendEntries3 = {};
        for i = 1:valid_count
            dl_v = GroupData(i).dl(GroupData(i).dl <= limit_dl);
            edges = linspace(0, limit_dl, Bins_1D+1); centers = edges(1:end-1) + diff(edges)/2;
            pdf = histcounts(dl_v, edges) / (length(dl_v) * (edges(2)-edges(1)));
            pidx = pdf > 0; c_idx = mod(i-1, size(Colors, 1)) + 1;
            
            scatter(centers(pidx), pdf(pidx), Marker_Size, Colors(c_idx,:), 'filled', ...
                'MarkerFaceAlpha', Alpha_Base, 'MarkerEdgeColor', 'none');
            LegendEntries3{i} = GroupData(i).name;
        end
        legend(LegendEntries3, 'Location', 'northeast', 'FontSize', FontSize_Legend, 'Box', 'off');
        xlabel('Jumping Length \Deltal (nm)', 'FontWeight', 'bold'); ylabel('Probability Density, G', 'FontWeight', 'bold');
        xlim([0, limit_dl]); ylim([1e-5, max(ylim)*2]);
    end

    % -----------------------------------------------------------------
    % [图 4] 均方位移 (MSD) 与 D 系数拟合图
    % -----------------------------------------------------------------
    if Enable_MSD
        figure('Name', 'Mean Squared Displacement', 'Position', [250, 250, 650, 500]);
        hold on; box on; 
        set(gca, 'FontSize', FontSize_Axis, 'LineWidth', LineWidth_Base, 'TickDir', 'in'); 
        
        LegendEntries4 = {}; Handles4 = [];
        X_time = (1:Max_MSD_Frames) * Dt_Actual; 
        [~, fit_idx] = min(abs(X_time - LinearT_Fit)); 
        if fit_idx < 2, fit_idx = min(10, Max_MSD_Frames); end
        
        for i = 1:valid_count
            c_idx = mod(i-1, size(Colors, 1)) + 1; current_color = Colors(c_idx, :);
            MSD_m2 = GroupData(i).msd * 10^(-18); 
            
            h_sc = scatter(X_time, MSD_m2, Marker_Size, current_color, 'filled', 'MarkerFaceAlpha', Alpha_Base);
            coef = polyfit(X_time(1:fit_idx), MSD_m2(1:fit_idx), 1);
            plot(X_time(1:fit_idx*2), polyval(coef, X_time(1:fit_idx*2)), '--', 'Color', current_color, 'LineWidth', LineWidth_Base+0.5);
            
            D_coeff = coef(1) / 4; 
            LegendEntries4{i} = sprintf('%s (D = %.2e)', GroupData(i).name, D_coeff);
            Handles4 = [Handles4, h_sc]; %#ok<AGROW>
        end
        legend(Handles4, LegendEntries4, 'Location', 'northwest', 'FontSize', FontSize_Legend-1, 'Box', 'off');
        xlabel('Time \tau (s)', 'FontWeight', 'bold'); ylabel('MSD (m^2)', 'FontWeight', 'bold');
        xlim([0, max(X_time)]);
    end

    fprintf('>>> 绘图全流程结束！请查看生成的图表。\n');
end