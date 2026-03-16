%% 吸附时间分布参数影响分析 - 终极整合版 (3x1)
clear; clc; close all;

% --- 基础全局参数 ---
N = 1.5e6;              % 样本数量
Mean_Anchor = 5.0;      % 锚定均值
FontSize = 10;
% 经典高对比度配色 (用于 A, B 图)
Colors_Main = [0, 0.447, 0.741; 0.85, 0.325, 0.098; 0.929, 0.694, 0.125; ...
               0.494, 0.184, 0.556; 0.466, 0.674, 0.188];

figure('Color', 'w', 'Position', [100, 50, 600, 950]); 

% =========================================================
% (A) 指数分布 - 扫描参数 tau (均值)
% =========================================================
subplot(3,1,1); hold on; box on;
taus = [1, 3, 5, 8, 12]; 
for i = 1:length(taus)
    t_exp = -taus(i) * log(1 - rand(N, 1));
    [f, x] = histcounts(t_exp, linspace(0, 40, 100), 'Normalization', 'pdf');
    lw = 2.0; if taus(i) == 5, lw = 4.0; end % 突出显示均值为5
    plot(x(1:end-1)+diff(x)/2, f, 'LineWidth', lw, 'Color', Colors_Main(i,:), ...
         'DisplayName', sprintf('\\tau = %g', taus(i)));
end
title('\bf(a) Exponential: Effect of Mean \tau', 'FontSize', FontSize+2);
ylabel('PDF'); xlim([0, 40]); ylim([0, 1.0]);
legend('Location', 'northeast', 'Box', 'off');
set(gca, 'TickDir', 'in', 'LineWidth', 1.1);

% =========================================================
% (B) 均匀分布 - 扫描均值组 [0, 2m] (无负半轴)
% =========================================================
subplot(3,1,2); hold on; box on;
means_uni = [1, 3, 5, 7, 9]; 
for i = 1:length(means_uni)
    m = means_uni(i);
    % 范围 [0, 2*m], 中心在 m
    t_uni = 2 * m * rand(N, 1);
    [f, x] = histcounts(t_uni, linspace(0, 20, 150), 'Normalization', 'pdf');
    lw = 2.0; if m == 5, lw = 4.0; end
    plot(x(1:end-1)+diff(x)/2, f, 'LineWidth', lw, 'Color', Colors_Main(i,:), ...
         'DisplayName', sprintf('Mean=%g, Range[0,%g]', m, 2*m));
end
title('\bf(b) Uniform: Scan Means (Symmetric Range [0, 2\mu])', 'FontSize', FontSize+2);
ylabel('PDF'); xlim([0, 20]); ylim([0, 1.2]);
legend('Location', 'northeast', 'Box', 'off');
set(gca, 'TickDir', 'in', 'LineWidth', 1.1);

% =========================================================
% (C) 幂律分布 - 增长到衰减的物理演变 (均值锚定 5.0)
% =========================================================
subplot(3,1,3); hold on; box on;
% 采用你提供的配色和参数
alphas_pow = [-5.0, -2.0, -0.5, 2.5, 3.5, 5.5]; 
Colors_Pow = [0.1, 0.5, 0.8;  0.2, 0.6, 0.9;  0.4, 0.7, 1.0; ... % 蓝色系(负)
              1.0, 0.4, 0.2;  0.8, 0.2, 0.1;  0.6, 0.0, 0.0];    % 红色系(正)

U = rand(N, 1);
for i = 1:length(alphas_pow)
    a = alphas_pow(i);
    if a < 1 % 增长型或发散型 (需要上截断 t_max)
        k = -a; 
        t_max = Mean_Anchor * (k + 2) / (k + 1);
        t_pow = t_max * U.^(1 / (k + 1));
        edges = linspace(0, t_max, 100);
        [f, x] = histcounts(t_pow, edges, 'Normalization', 'pdf');
        plot(x(1:end-1)+diff(x)/2, f, 'LineWidth', 2.5, 'Color', Colors_Pow(i,:), ...
             'DisplayName', sprintf('\\alpha = %.1f (Growth)', a));
    else % 衰减型 (Pareto分布，需要下截断 t_min)
        t_min = Mean_Anchor * (a - 2) / (a - 1);
        t_pow = t_min * (1 - U).^(1 / (1 - a));
        edges = logspace(log10(t_min), 2, 100); 
        [f, x] = histcounts(t_pow, edges, 'Normalization', 'pdf');
        plot(x(1:end-1)+diff(x)/2, f, 'LineWidth', 2.5, 'Color', Colors_Pow(i,:), ...
             'DisplayName', sprintf('\\alpha = %.1f (Decay)', a));
    end
end

% 幂律图特有装饰 (按照你的代码设置)
set(gca, 'XScale', 'linear', 'YScale', 'log', 'FontSize', FontSize);
xlabel('Adsorption Time t_{ads}', 'FontWeight', 'bold');
ylabel('PDF (Log Scale)', 'FontWeight', 'bold');
title('\bf(c) Power Law: Transition Growth to Decay (Mean=5.0)', 'FontSize', FontSize+2);
xlim([0, 30]); ylim([1e-3, 5]); 
grid on; grid minor;
legend('Location', 'northeast', 'NumColumns', 2, 'Box', 'off', 'FontSize', 8);

% 绘制均值参考线
plot([5 5], [1e-4 10], '--k', 'LineWidth', 1.2, 'HandleVisibility', 'off');
text(5.2, 2, 'Mean = 5.0', 'FontWeight', 'bold');

% 全局标题调整
sgtitle('Comprehensive Analysis of Adsorption Time Distributions', 'FontWeight', 'bold', 'FontSize', 14);