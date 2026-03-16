function Smart_Folder_Plot()
    % =====================================================================
    % IBD-HPC 全能单分子分析控制台 (终极融合版)
    % 特性：极简积木式过滤 + 顶刊级 Rep 独立 MSD 误差带渲染 + 强制坐标锁定
    % =====================================================================
    clc; clear; close all;
    
    % ---------------------------------------------------------------------
    % [1. 模块生成开关]
    % ---------------------------------------------------------------------
    Enable_1D_PDF      = true;  
    Enable_2D_Contour  = true;  
    Enable_JumpLength  = true;  
    Enable_XY_Compare  = true;
    Enable_MSD         = false;  
    
    % ---------------------------------------------------------------------
    % [2. 科学正交对比过滤面板] 
    % ---------------------------------------------------------------------
    num = 5;
    
    switch num
        case 1
            ControlVars = {'Tads50.00_', 'Vx_0_'}; 
            InvestigateVars = {'PowerLaw_TI-2.5', 'PowerLaw_TI2.5', 'Exp', 'Uniform'};
        case 2
            ControlVars     = {'PowerLaw_TI-2.5', 'ratio_0k'}; 
            InvestigateVars = {'Tads0.001','Tads0.005','Tads0.010','Tads0.030','Tads0.110','Tads0.150'};   
        case 3
            ControlVars     = {'Uniform','Tads1.00'}; 
            InvestigateVars = {'ratio_0k','ratio_1e-07k', 'ratio_1e-06k','ratio_1e-05k','ratio_0.0001k','ratio_0.001k','ratio_0.01k','ratio_0.03k'  ,'ratio_0.05k'  ,'ratio_0.08k','ratio_0.1k','ratio_0.2k','ratio_0.3k','ratio_0.4k','ratio_0.5k'}; 
        case 4
            ControlVars     = {'ratio_0.009k','Tads1.00'}; 
            InvestigateVars = {'PowerLaw_TI-2.5', 'PowerLaw_TI2.5', 'Exp', 'Uniform'}; 
        case 5
            ControlVars     = {'Exp', 'Tads0.04','ratio_0k'}; 
            InvestigateVars = {'DS10_', 'DS20_', 'DS40_', 'DS60_', 'DS80_', 'DS100_'};
    end
    
    % ---------------------------------------------------------------------
    % [3. 全自动自适应与离散化参数]
    % ---------------------------------------------------------------------
    LagSteps        = 1;        
    Dt_Default      = 0.02;     
    AutoPrctile     = 99.8;     
    Bins_1D         = 120;      
    Bins_2D         = 80;       
    ContourLevels   = 4;        
    Max_MSD_Frames  = 10000;    
    LinearT_Fit     = 50;       
    
    % ---------------------------------------------------------------------
    % [4. 视觉规范]
    % ---------------------------------------------------------------------
    FontSize_Axis   = 16;       
    FontSize_Legend = 12;       
    LineWidth_Base  = 1.5;      
    Marker_Size     = 50;       
    Alpha_Base      = 0.8;      
    Colors = [0.00, 0.45, 0.74; 0.85, 0.33, 0.10; 0.93, 0.69, 0.13; 
              0.49, 0.18, 0.56; 0.47, 0.67, 0.19; 0.30, 0.75, 0.93];

    % ---------------------------------------------------------------------
    % [5. 制坐标轴范围控制 (用于论文完美复现)]
    % ---------------------------------------------------------------------
    % 将开关设为 true 即可锁定下方设定的范围；设为 false 则退回自动缩放
    ForceLimit_1D_dx   = true;   XLim_1D_dx = [-500, 500];     YLim_1D_dx = [1e-6, 1];
    ForceLimit_1D_dy   = true;   XLim_1D_dy = [-500, 500];     YLim_1D_dy = [1e-6, 1];
    ForceLimit_Jump    = true;   XLim_Jump  = [0, 2000];        YLim_Jump  = [1e-5, 1];
    ForceLimit_MSD     = false;  XLim_MSD   = [1e-2, 1e2];     YLim_MSD   = [1e-18, 1e-12];
    ForceLimit_XY_Comp = true;   XLim_XY    = [-500, 500];     YLim_XY    = [1e-6, 1];
              
    %% ================== 核心执行区 ==================
    fprintf('>>> 启动 HPC 分析引擎 (Rep 独立统计版)...\n');
    
    baseResultDir = fullfile(pwd, 'Simulation_Results');
    Target_Dir = fullfile(pwd, 'analysis'); 
    if ~exist(Target_Dir, 'dir') && exist(baseResultDir, 'dir')
        taskDirs = dir(fullfile(baseResultDir, 'Task_*'));
        if ~isempty(taskDirs)
            [~, idx] = max([taskDirs.datenum]);
            Target_Dir = fullfile(baseResultDir, taskDirs(idx).name);
            fprintf('>>> 未找到 analysis 文件夹，已重定向到最新数据: %s\n', taskDirs(idx).name);
        end
    end
    if ~exist(Target_Dir, 'dir'), error('找不到数据文件夹！'); end
    
    all_items = dir(Target_Dir);
    subfolders = all_items([all_items.isdir] & ~ismember({all_items.name}, {'.', '..'}));
    GroupData = struct();
    valid_count = 0;
    global_max_dx = 0; global_max_dl = 0; Dt_Actual = Dt_Default; 
    
    % 预先生成对数降采样的 MSD 帧数索引（保证所有 Rep 时间轴一致）
    calc_steps = unique(round([1:50, logspace(log10(51), log10(Max_MSD_Frames), 100)]));
    
    %% 【第一阶段：数据系综池化与 Rep 独立运算】
    for i = 1:length(InvestigateVars)
        current_var = InvestigateVars{i};
        
        match_mask = true(1, length(subfolders));
        for c = 1:length(ControlVars)
            match_mask = match_mask & contains({subfolders.name}, ControlVars{c}); 
        end
        match_mask = match_mask & contains({subfolders.name}, current_var);
        matching_folders = subfolders(match_mask);
        
        if isempty(matching_folders), continue; end
        valid_count = valid_count + 1;
        num_reps = length(matching_folders);
        
        dx_merged = []; dy_merged = []; dl_merged = [];
        % 为当前条件预分配 Rep 独立容器
        RepMSDs = NaN(num_reps, length(calc_steps)); 
        
        fprintf('[+] 融合特征组: %s (提取到 %d 个独立 Rep)...\n', current_var, num_reps);
        
        for f = 1:num_reps
            folder_path = fullfile(Target_Dir, matching_folders(f).name);
            mat_files = dir(fullfile(folder_path, '*.mat'));
            
            for rep_f = 1:length(mat_files)
                try
                    data = load(fullfile(folder_path, mat_files(rep_f).name), 'positionlist', 'p');
                    if isfield(data, 'p'), Dt_Actual = data.p(1); end 
                    
                    if isfield(data, 'positionlist') && size(data.positionlist, 2) >= 3
                        pos = data.positionlist;
                        
                        % =====================================================
                        % 核心修复 1：复刻原论文的 Sub_MergingLocalizationsInSameFrame
                        % 按帧号(Frame)将多次吸附的坐标合并为该帧的"光学质心"
                        % =====================================================
                        frames = double(pos(:, 3));
                        [u_frames, ~, idx] = unique(frames); % 提取唯一的帧号
                        
                        % 计算该帧内的平均坐标
                        mean_X = accumarray(idx, pos(:, 1)) ./ accumarray(idx, 1);
                        mean_Y = accumarray(idx, pos(:, 2)) ./ accumarray(idx, 1);
                        
                        % =====================================================
                        % 核心修复 2：注入显微镜定位误差 (Localization Error)
                        % 用于平滑 x=0 处的突兀断层，形成高斯基座
                        % =====================================================
                        sigma_loc = 0; % 定位精度设为 25nm
                        obs_X = mean_X + randn(size(mean_X)) * sigma_loc;
                        obs_Y = mean_Y + randn(size(mean_Y)) * sigma_loc;
                        
                        % =====================================================
                        % 核心修复 3：严格计算"相邻帧"的光学位移
                        % =====================================================
                        % 判断两帧是否紧挨着（dFrame == 1），跨帧丢失的断点不能算作一次位移
                        valid_jumps = diff(u_frames) == 1; 
                        
                        dx_now = obs_X(2:end) - obs_X(1:end-1);
                        dy_now = obs_Y(2:end) - obs_Y(1:end-1);
                        
                        % 仅保留相邻帧的数据压入系综
                        dx_merged = [dx_merged; dx_now(valid_jumps)]; %#ok<AGROW>
                        dy_merged = [dy_merged; dy_now(valid_jumps)]; %#ok<AGROW>
                        dl_merged = [dl_merged; sqrt(dx_now(valid_jumps).^2 + dy_now(valid_jumps).^2)]; %#ok<AGROW>
                        
                        % =====================================================
                        % 核心修复 4：严谨的连续时间轴 MSD 计算
                        % =====================================================
                        if Enable_MSD
                            % 为保证跨越丢帧依然能正确计算滞后时间，构建包含 NaN 的连续时间轴
                            max_f = max(u_frames);
                            min_f = min(u_frames);
                            full_len = max_f - min_f + 1;
                            
                            contig_X = NaN(full_len, 1);
                            contig_Y = NaN(full_len, 1);
                            
                            % 将观测到的坐标填入对应时间轴
                            frame_indices = u_frames - min_f + 1;
                            contig_X(frame_indices) = obs_X;
                            contig_Y(frame_indices) = obs_Y;
                            
                            % 基于时间滞后步长(Lag steps)计算均方位移
                            for s_idx = 1:length(calc_steps)
                                step = calc_steps(s_idx);
                                if full_len > step
                                    sq_disp = (contig_X(1+step:end) - contig_X(1:end-step)).^2 + ...
                                              (contig_Y(1+step:end) - contig_Y(1:end-step)).^2;
                                    valid_sq = sq_disp(~isnan(sq_disp));
                                    if ~isempty(valid_sq)
                                        RepMSDs(rep_f, s_idx) = mean(valid_sq);
                                    end
                                end
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
        GroupData(valid_count).num_reps = num_reps;
        
        % 核心修复：计算组内 Rep 的均值和标准误(SEM)
        if Enable_MSD
            GroupData(valid_count).msd_mean = mean(RepMSDs, 1, 'omitnan');
            GroupData(valid_count).msd_sem = std(RepMSDs, 0, 1, 'omitnan') / sqrt(num_reps);
        end
        
        if any(valid_mask)
            global_max_dx = max([global_max_dx, prctile(abs(GroupData(valid_count).dx), AutoPrctile)]);
            global_max_dl = max(global_max_dl, prctile(GroupData(valid_count).dl, AutoPrctile));
        end
    end
    if valid_count == 0, error('未提取到匹配数据！'); end
    
    limit_dx = ceil((max(global_max_dx, 50) * 1.15) / 10) * 10;
    limit_dl = ceil((max(global_max_dl, 50) * 1.15) / 10) * 10;
    XLimRange = [-limit_dx, limit_dx];
    
    %% 【第二阶段：图表渲染】
    % -----------------------------------------------------------------
    % [图 1] 1D dx PDF 
    % -----------------------------------------------------------------
    if Enable_1D_PDF
        figure('Name', '1D dx PDF', 'Position', [100, 100, 650, 500]); 
        hold on; box on; 
        set(gca, 'YScale', 'log', 'FontSize', FontSize_Axis, 'LineWidth', LineWidth_Base, ...
                 'TickDir', 'in', 'XGrid', 'off', 'YGrid', 'off'); 
        
        L1={}; 
        for i = 1:valid_count
            dx_v = GroupData(i).dx(GroupData(i).dx >= XLimRange(1) & GroupData(i).dx <= XLimRange(2));
            edges = linspace(XLimRange(1), XLimRange(2), Bins_1D+1); 
            c = edges(1:end-1) + diff(edges)/2;
            pdf = histcounts(dx_v, edges) / (length(dx_v) * (edges(2) - edges(1)));
            
            pidx = pdf > 0; 
            c_idx = mod(i-1, size(Colors, 1)) + 1;
            scatter(c(pidx), pdf(pidx), Marker_Size, Colors(c_idx,:), 'filled', ...
                'MarkerFaceAlpha', Alpha_Base, 'MarkerEdgeColor', 'none');
            L1{i} = GroupData(i).name;
        end
        
        xlabel('dx (nm)', 'FontWeight', 'bold'); 
        ylabel('Probability Density G(dx)', 'FontWeight', 'bold'); 
        legend(L1, 'Location', 'northeast', 'FontSize', FontSize_Legend-2, 'Box', 'off'); 
        
        % 🎯 应用手动坐标轴控制
        if ForceLimit_1D_dx
            xlim(XLim_1D_dx); ylim(YLim_1D_dx);
        else
            xlim(XLimRange); 
        end
    end
    
    % -----------------------------------------------------------------
    % [图 2] 1D dy PDF 
    % -----------------------------------------------------------------
    if Enable_2D_Contour
        figure('Name', '1D dy PDF', 'Position', [150, 150, 650, 500]); 
        hold on; box on; 
        set(gca, 'YScale', 'log', 'FontSize', FontSize_Axis, 'LineWidth', LineWidth_Base, ...
                 'TickDir', 'in', 'XGrid', 'off', 'YGrid', 'off'); 
        
        dy_LimRange = [-300, 300]; 
        L2={}; 
        for i = 1:valid_count
            dy_v = GroupData(i).dy(GroupData(i).dy >= dy_LimRange(1) & GroupData(i).dy <= dy_LimRange(2));
            edges = linspace(dy_LimRange(1), dy_LimRange(2), Bins_1D + 1); 
            c = edges(1:end-1) + diff(edges)/2;
            pdf = histcounts(dy_v, edges) / (length(dy_v) * (edges(2) - edges(1)));
            
            pidx = pdf > 0; 
            c_idx = mod(i-1, size(Colors, 1)) + 1;
            scatter(c(pidx), pdf(pidx), Marker_Size, Colors(c_idx,:), 'filled', ...
                'MarkerFaceAlpha', Alpha_Base, 'MarkerEdgeColor', 'none');
            L2{i} = GroupData(i).name;
        end
        
        xlabel('dy (nm)', 'FontWeight', 'bold');
        ylabel('Probability Density G(dy)', 'FontWeight', 'bold');
        legend(L2, 'Location', 'northeast', 'FontSize', FontSize_Legend-2, 'Box', 'off');
        
        % 🎯 应用手动坐标轴控制
        if ForceLimit_1D_dy
            xlim(XLim_1D_dy); ylim(YLim_1D_dy);
        else
            xlim(dy_LimRange); 
        end
    end
    
    % --------- [图 3] Jump Length ---------
    if Enable_JumpLength
        figure('Name', 'Jump Length', 'Position', [200, 200, 650, 500]); hold on; box on; 
        set(gca, 'YScale', 'log', 'FontSize', FontSize_Axis, 'LineWidth', LineWidth_Base, 'TickDir', 'in'); 
        L3={}; for i=1:valid_count
            dl_v=GroupData(i).dl(GroupData(i).dl<=limit_dl);
            edges=linspace(0,limit_dl,Bins_1D+1); c=edges(1:end-1)+diff(edges)/2;
            pdf=histcounts(dl_v,edges)/(length(dl_v)*(edges(2)-edges(1))); pidx=pdf>0; c_idx=mod(i-1,size(Colors,1))+1;
            scatter(c(pidx),pdf(pidx),Marker_Size,Colors(c_idx,:),'filled','MarkerFaceAlpha',Alpha_Base,'MarkerEdgeColor','none');
            L3{i}=GroupData(i).name;
        end
        legend(L3,'Location','northeast','FontSize',FontSize_Legend,'Box','off'); 
        xlabel('\Deltal (nm)','FontWeight','bold'); ylabel('G','FontWeight','bold'); 
        
        % 🎯 应用手动坐标轴控制
        if ForceLimit_Jump
            xlim(XLim_Jump); ylim(YLim_Jump);
        else
            xlim([0, limit_dl]); ylim([1e-5, max(ylim)*2]);
        end
    end
    
    % --------- [图 4] MSD 均方位移 ---------
    if Enable_MSD
        figure('Name', 'MSD', 'Position', [250, 250, 650, 500]); hold on; box on; 
        set(gca, 'FontSize', FontSize_Axis, 'LineWidth', LineWidth_Base, 'TickDir', 'in'); 
        L4={}; H4=[];
        
        for i = 1:valid_count
            c_idx = mod(i-1, size(Colors, 1)) + 1; current_color = Colors(c_idx, :);
            
            valid_idx = ~isnan(GroupData(i).msd_mean) & (GroupData(i).msd_mean > 0);
            X_time = calc_steps(valid_idx) * Dt_Actual; 
            Y_mean = GroupData(i).msd_mean(valid_idx) * 10^(-18); 
            Y_err  = GroupData(i).msd_sem(valid_idx) * 10^(-18); 
            
            if GroupData(i).num_reps > 1 && sum(Y_err > 0) > 0
                Y_upper = Y_mean + Y_err;
                Y_lower = max(Y_mean - Y_err, min(Y_mean)*0.1); 
                fill([X_time, fliplr(X_time)], [Y_upper, fliplr(Y_lower)], current_color, ...
                     'FaceAlpha', 0.2, 'EdgeColor', 'none', 'HandleVisibility', 'off');
            end
            
            h_line = plot(X_time, Y_mean, 'o-', 'Color', current_color, 'MarkerFaceColor', current_color, ...
                          'MarkerSize', Marker_Size/8, 'LineWidth', LineWidth_Base);
            
            fit_mask = X_time <= LinearT_Fit;
            if sum(fit_mask) >= 2
                X_fit = X_time(fit_mask); Y_fit = Y_mean(fit_mask);
                coef = polyfit(X_fit, Y_fit, 1);
                plot_len = min(length(X_time), sum(fit_mask)*2);
                Y_fit_line = polyval(coef, X_time(1:plot_len));
                valid_line = Y_fit_line > 0;
                plot(X_time(valid_line), Y_fit_line(valid_line), '--', 'Color', current_color, 'LineWidth', LineWidth_Base+0.5, 'HandleVisibility', 'off');
                D_coeff = coef(1) / 4; 
                L4{i} = sprintf('%s (D=%.2e)', GroupData(i).name, D_coeff);
            else
                L4{i} = GroupData(i).name;
            end
            H4 = [H4, h_line]; 
        end
        legend(H4, L4, 'Location', 'northwest', 'FontSize', FontSize_Legend-1, 'Box', 'off');
        xlabel('Time \tau (s)', 'FontWeight', 'bold'); ylabel('EA-MSD (m^2)', 'FontWeight', 'bold');
        set(gca, 'XScale', 'log', 'YScale', 'log');
        
        % 🎯 应用手动坐标轴控制
        if ForceLimit_MSD
            xlim(XLim_MSD); ylim(YLim_MSD);
        else
            xlim([min(X_time), max(X_time)]); 
        end
    end
    
    % -----------------------------------------------------------------
    % [图 5] dx & dy 对照图 (精简图例版)
    % -----------------------------------------------------------------
    if Enable_XY_Compare
        figure('Name', 'dx-dy Robust Infinite Fit (No Zero)', 'Position', [250, 250, 650, 500]); 
        hold on; box on;
        set(gca, 'YScale', 'log', 'FontSize', FontSize_Axis, 'LineWidth', LineWidth_Base, ...
                 'TickDir', 'in', 'XGrid', 'off', 'YGrid', 'off');
        Y_Bottom = 1e-6; 
        for i = 1:valid_count
            c_idx = mod(i-1, size(Colors, 1)) + 1;
            this_color = Colors(c_idx,:);
            
            % =========================================================
            % 1. dx
            % =========================================================
            dx_v = GroupData(i).dx(GroupData(i).dx >= XLimRange(1) & GroupData(i).dx <= XLimRange(2));
            edges_x = linspace(XLimRange(1), XLimRange(2), Bins_1D+1);
            cx = edges_x(1:end-1) + diff(edges_x)/2;
            pdf_x = histcounts(dx_v, edges_x) / (length(dx_v) * (edges_x(2)-edges_x(1)));
            
            bin_w_x = edges_x(2) - edges_x(1);
            pidx_x = (pdf_x > 0) & (abs(cx) > bin_w_x * 0.6); 
            cx_val = cx(pidx_x); pdf_x_val = pdf_x(pidx_x);
            
            scatter(cx_val, pdf_x_val, 15, this_color, 'filled', 'MarkerFaceAlpha', 0.12, 'HandleVisibility', 'off'); 
            
            dx_moving = dx_v(abs(dx_v) > 1e-4); 
            if isempty(dx_moving), med_x = 0; else, med_x = median(dx_moving); end
            
            thresh_x = max(pdf_x_val) * 1e-5; 
            min_pts_for_fit = 4;
            
            m_L_x = (cx_val <= med_x) & (pdf_x_val > thresh_x);
            m_R_x = (cx_val > med_x) & (pdf_x_val > thresh_x);
            
            p_Lx = [0, -inf]; 
            if sum(m_L_x) >= min_pts_for_fit
                X_mat = [cx_val(m_L_x)', ones(sum(m_L_x), 1)]; W = diag(pdf_x_val(m_L_x));
                beta = (X_mat' * W * X_mat) \ (X_mat' * W * log(pdf_x_val(m_L_x)')); 
                if beta(1) > 0, p_Lx = [beta(1), beta(2)]; end
            end
            
            p_Rx = [0, -inf];
            if sum(m_R_x) >= min_pts_for_fit
                X_mat = [cx_val(m_R_x)', ones(sum(m_R_x), 1)]; W = diag(pdf_x_val(m_R_x));
                beta = (X_mat' * W * X_mat) \ (X_mat' * W * log(pdf_x_val(m_R_x)')); 
                if beta(1) < 0, p_Rx = [beta(1), beta(2)]; end
            end
            
            if p_Lx(2) > -inf && p_Rx(2) > -inf
                int_x = (p_Lx(2) - p_Rx(2)) / (p_Rx(1) - p_Lx(1));
                int_x = max(min(int_x, med_x + bin_w_x*5), med_x - bin_w_x*5);
            else
                int_x = med_x;
            end
            
            x_start_x = max(XLimRange(1), (log(Y_Bottom) - p_Lx(2)) / p_Lx(1));
            x_end_x   = min(XLimRange(2), (log(Y_Bottom) - p_Rx(2)) / p_Rx(1));
            
            if isempty(dx_moving), skew_x = 0; else, skew_x = mean((dx_moving - mean(dx_moving)).^3) / (std(dx_moving)^3); end
            leg_main = sprintf('%s (\\gamma=%.2f)', GroupData(i).name, skew_x);
            
            if p_Lx(2) > -inf
                plot([x_start_x, int_x], [exp(polyval(p_Lx, x_start_x)), exp(polyval(p_Lx, int_x))], ...
                     '-', 'Color', this_color, 'LineWidth', 2.2, 'HandleVisibility', 'off');
            end
            if p_Rx(2) > -inf
                plot([int_x, x_end_x], [exp(polyval(p_Rx, int_x)), exp(polyval(p_Rx, x_end_x))], ...
                     '-', 'Color', this_color, 'LineWidth', 2.2, 'DisplayName', leg_main);
            end
            % =========================================================
            % 2. dy 
            % =========================================================
            dy_LimRange = [-300, 300]; 
            dy_v = GroupData(i).dy(GroupData(i).dy >= dy_LimRange(1) & GroupData(i).dy <= dy_LimRange(2));
            edges_y = linspace(dy_LimRange(1), dy_LimRange(2), Bins_1D+1);
            cy = edges_y(1:end-1) + diff(edges_y)/2;
            pdf_y = histcounts(dy_v, edges_y) / (length(dy_v) * (edges_y(2)-edges_y(1)));
            
            bin_w_y = edges_y(2) - edges_y(1);
            pidx_y = (pdf_y > 0) & (abs(cy) > bin_w_y * 0.6); 
            cy_val = cy(pidx_y); pdf_y_val = pdf_y(pidx_y);
            
            scatter(cy_val, pdf_y_val, 15, this_color, 'MarkerEdgeAlpha', 0.25, 'HandleVisibility', 'off'); 
            
            dy_moving = dy_v(abs(dy_v) > 1e-4);
            if isempty(dy_moving), med_y = 0; else, med_y = median(dy_moving); end
            
            m_L_y = (cy_val <= med_y) & (pdf_y_val > thresh_x);
            m_R_y = (cy_val > med_y) & (pdf_y_val > thresh_x);
            
            p_Ly = [0, -inf];
            if sum(m_L_y) >= min_pts_for_fit
                X_mat = [cy_val(m_L_y)', ones(sum(m_L_y), 1)]; W = diag(pdf_y_val(m_L_y));
                beta = (X_mat' * W * X_mat) \ (X_mat' * W * log(pdf_y_val(m_L_y)')); 
                if beta(1) > 0, p_Ly = [beta(1), beta(2)]; end
            end
            
            p_Ry = [0, -inf];
            if sum(m_R_y) >= min_pts_for_fit
                X_mat = [cy_val(m_R_y)', ones(sum(m_R_y), 1)]; W = diag(pdf_y_val(m_R_y));
                beta = (X_mat' * W * X_mat) \ (X_mat' * W * log(pdf_y_val(m_R_y)')); 
                if beta(1) < 0, p_Ry = [beta(1), beta(2)]; end
            end
            
            if p_Ly(2) > -inf && p_Ry(2) > -inf
                int_y = (p_Ly(2) - p_Ry(2)) / (p_Ry(1) - p_Ly(1));
            else
                int_y = med_y;
            end
            
            x_start_y = max(XLimRange(1), (log(Y_Bottom) - p_Ly(2)) / p_Ly(1));
            x_end_y   = min(XLimRange(2), (log(Y_Bottom) - p_Ry(2)) / p_Ry(1));
            
            if p_Ly(2) > -inf
                plot([x_start_y, int_y], [exp(polyval(p_Ly, x_start_y)), exp(polyval(p_Ly, int_y))], ...
                     '--', 'Color', this_color, 'LineWidth', 2.0, 'HandleVisibility', 'off');
            end
            if p_Ry(2) > -inf
                plot([int_y, x_end_y], [exp(polyval(p_Ry, int_y)), exp(polyval(p_Ry, x_end_y))], ...
                     '--', 'Color', this_color, 'LineWidth', 2.0, 'HandleVisibility', 'off');
            end
        end
        
        xlabel('Displacement (nm)', 'FontWeight', 'bold');
        ylabel('Probability Density G', 'FontWeight', 'bold');
        legend('Location', 'northeast', 'FontSize', FontSize_Legend-2, 'Box', 'off');
        
        % 🎯 应用手动坐标轴控制
        if ForceLimit_XY_Comp
            xlim(XLim_XY); ylim(YLim_XY);
        else
            xlim(XLimRange); ylim([Y_Bottom, max(ylim)*2]); 
        end
    end
    
%% --- [5] 自动化存图：平铺预览 + 比例锁定汇总图 (防变形版) ---
    fprintf('>>> 正在排列窗口：小图平铺，汇总展板比例锁定...\n');
    
    ctrl_str = strjoin(ControlVars, '_');
    inv_str  = strjoin(InvestigateVars, '_');
    folderName = sprintf('[%s][%s]', ctrl_str, inv_str);
    if length(folderName) > 150, folderName = [folderName(1:145), '...]']; end
    saveDir = fullfile(pwd, 'Saved_Figures', folderName);
    if ~exist(saveDir, 'dir'), mkdir(saveDir); end
    
    figList = findobj('Type', 'figure');
    [~, sortIdx] = sort([figList.Number]);
    figList = figList(sortIdx); 
    N = length(figList);
    
    scrsz = get(0, 'ScreenSize');
    sw = scrsz(3); sh = scrsz(4);
    small_h = sh * 0.35;         
    large_h = sh * 0.48;         
    large_y = 60;                
    small_y = large_y + large_h + 30; 
    figW = sw / 4;               
    
    for k = 1:N
        fig = figList(k);
        set(fig, 'WindowState', 'normal'); 
        set(fig, 'Position', [(k-1)*figW + 5, small_y, figW-10, small_h]);
        drawnow; 
        figName = fig.Name;
        if isempty(figName), figName = sprintf('Figure_%d', fig.Number); end
        safeFigName = strrep(figName, ' ', '_'); 
        savefig(fig, fullfile(saveDir, [safeFigName, '.fig']));
        set(fig, 'PaperPositionMode', 'manual', 'PaperUnits', 'inches', 'PaperPosition', [0, 0, 8, 6]); 
        try exportgraphics(fig, fullfile(saveDir, [safeFigName, '.jpg']), 'Resolution', 300); catch, end
    end
    
    if N > 1
        fig_combo = figure('Name', 'Combined_Panel', 'Color', 'w', 'WindowState', 'maximized');
        drawnow; 
        
        cols = 2; rows = ceil(N / cols);
        for k = 1:N
            temp_ax = subplot(rows, cols, k);
            target_pos = get(temp_ax, 'Position'); delete(temp_ax);
            
            cloned_objs = copyobj(get(figList(k), 'Children'), fig_combo);
            cloned_ax = findobj(cloned_objs, 'flat', 'Type', 'axes');
            
            if ~isempty(cloned_ax)
                set(cloned_ax(1), 'Position', target_pos);
                title(cloned_ax(1), sprintf('(%c)', 96+k), 'Units', 'normalized', ...
                      'Position', [-0.1, 1.05, 0], 'FontSize', 18, 'FontWeight', 'bold');
            end
        end
        
        set(fig_combo, 'PaperPositionMode', 'manual', 'PaperUnits', 'inches', 'PaperPosition', [0, 0, 12, 9]);
        
        savefig(fig_combo, fullfile(saveDir, 'Combined_Panel.fig'));
        try 
            exportgraphics(fig_combo, fullfile(saveDir, 'Combined_Panel.jpg'), 'Resolution', 300); 
        catch
            print(fig_combo, fullfile(saveDir, 'Combined_Panel.jpg'), '-djpeg', '-r300');
        end
        
        set(fig_combo, 'PaperPositionMode', 'auto');
        figure(fig_combo); 
    end
    
    fprintf('>>> 排版完成。\n');
end