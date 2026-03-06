% 随机数分布验证：生成+拟合+理论对比（含公式标注，修复维度不匹配错误）
clear; clc; close all;
rng('shuffle');  % 初始化随机数种子，保证结果可复现

%% ===================== 核心参数设置 =====================
N = 50000;               % 随机数数量（越大拟合效果越优）
num_bins = 150;          % 直方图分箱数（分箱越多越平滑）
sample_points = 2000;    % 曲线采样点数（提升曲线平滑度）

% 分布参数配置（可按需修改）
exp_mean = 5;            % 指数分布均值
unif_mean = 5;           % 均匀分布均值
unif_range = 4;          % 均匀分布区间长度
power_alpha = 3;         % 幂律分布指数（需满足alpha>2，保证均值存在）
power_mean = 5;          % 幂律分布均值

%% ===================== 生成随机数 =====================
% 1. 指数分布随机数：f(x) = λe^(-λx)，λ=1/exp_mean
lambda_theo = 1 / exp_mean;
exp_rand = -log(1 - rand(N, 1)) / lambda_theo;

% 2. 均匀分布随机数：f(x)=1/(b-a)，a=unif_mean-range/2, b=unif_mean+range/2
unif_a = unif_mean - unif_range/2;
unif_b = unif_mean + unif_range/2;
unif_rand = unif_a + (unif_b - unif_a) * rand(N, 1);

% 3. 幂律分布随机数：f(x)=(α-1)xmin^(α-1)/x^α（x≥xmin），xmin由均值推导
power_xmin_theo = power_mean * (power_alpha - 2) / (power_alpha - 1);
power_rand = power_xmin_theo * (1 - rand(N, 1)).^(1 / (1 - power_alpha));

%% ===================== 定义拟合函数 =====================
% 指数分布拟合：参数p(1)=λ（使用元素级运算符，避免矩阵运算错误）
exp_fit_fun = @(p, x) p(1) .* exp(-p(1) .* x);
% 均匀分布拟合：参数p(1)=a, p(2)=b（返回与x等长的概率密度）
unif_fit_fun = @(p, x) (x >= p(1) & x <= p(2)) .* (1 / (p(2) - p(1)));
% 幂律分布拟合：参数p(1)=α, p(2)=xmin（元素级运算）
power_fit_fun = @(p, x) (x >= p(2)) .* ((p(1)-1)*p(2)^(p(1)-1) ./ (x .^ p(1)));

%% ===================== 计算直方图数据（修复维度不匹配核心） =====================
% --- 指数分布：获取等长的x中心和概率密度y ---
[exp_counts, exp_edges] = histcounts(exp_rand, num_bins, 'Normalization', 'pdf');
exp_x_centers = (exp_edges(1:end-1) + exp_edges(2:end))/2;  % 长度=num_bins
% 确保y数据与x中心等长（exp_counts是概率密度，长度=num_bins）
exp_y_pdf = exp_counts;  

% --- 均匀分布 ---
[unif_counts, unif_edges] = histcounts(unif_rand, num_bins, 'Normalization', 'pdf');
unif_x_centers = (unif_edges(1:end-1) + unif_edges(2:end))/2;
unif_y_pdf = unif_counts;

% --- 幂律分布 ---
[power_counts, power_edges] = histcounts(power_rand, num_bins, 'Normalization', 'pdf');
power_x_centers = (power_edges(1:end-1) + power_edges(2:end))/2;
power_y_pdf = power_counts;

%% ===================== 非线性拟合（维度完全匹配） =====================
% 1. 指数分布拟合（初始猜测：λ=1/样本均值）
exp_p0 = [1/mean(exp_rand)];  
exp_p_fit = nlinfit(exp_x_centers, exp_y_pdf, exp_fit_fun, exp_p0);

% 2. 均匀分布拟合（初始猜测：a=样本最小值，b=样本最大值）
unif_p0 = [min(unif_rand), max(unif_rand)];  
unif_p_fit = nlinfit(unif_x_centers, unif_y_pdf, unif_fit_fun, unif_p0);

% 3. 幂律分布拟合（初始猜测：理论α和xmin）
power_p0 = [power_alpha, power_xmin_theo];  
power_p_fit = nlinfit(power_x_centers, power_y_pdf, power_fit_fun, power_p0);

%% ===================== 计算拟合优度R²（量化拟合效果） =====================
% 指数分布R²
exp_y_fit = exp_fit_fun(exp_p_fit, exp_x_centers);
exp_ss_total = sum((exp_y_pdf - mean(exp_y_pdf)).^2);
exp_ss_res = sum((exp_y_pdf - exp_y_fit).^2);
exp_r2 = 1 - exp_ss_res / exp_ss_total;

% 均匀分布R²
unif_y_fit = unif_fit_fun(unif_p_fit, unif_x_centers);
unif_ss_total = sum((unif_y_pdf - mean(unif_y_pdf)).^2);
unif_ss_res = sum((unif_y_pdf - unif_y_fit).^2);
unif_r2 = 1 - unif_ss_res / unif_ss_total;

% 幂律分布R²
power_y_fit = power_fit_fun(power_p_fit, power_x_centers);
power_ss_total = sum((power_y_pdf - mean(power_y_pdf)).^2);
power_ss_res = sum((power_y_pdf - power_y_fit).^2);
power_r2 = 1 - power_ss_res / power_ss_total;

%% ===================== 绘制对比图（含公式标注） =====================
figure('Position', [100 100 1200 900]);  % 设置图片位置和大小

% ---------- 子图1：指数分布 ----------
subplot(3,1,1);
% 绘制直方图
histogram(exp_rand, num_bins, 'Normalization', 'pdf', 'EdgeColor', 'none', 'FaceColor', [0.8 0.8 1]);
hold on;
% 生成曲线x轴
exp_x = linspace(0, max(exp_rand), sample_points);
% 绘制拟合曲线
exp_y_fit_curve = exp_fit_fun(exp_p_fit, exp_x);
plot(exp_x, exp_y_fit_curve, 'r-', 'LineWidth', 2, 'DisplayName', '拟合曲线');
% 绘制理论曲线
exp_y_theo = lambda_theo * exp(-lambda_theo * exp_x);
plot(exp_x, exp_y_theo, 'k--', 'LineWidth', 1.5, 'DisplayName', '理论曲线');
% 构建公式文本（保留3位小数）
exp_theo_eq = sprintf('理论: f(x) = %.3f e^{-%.3f x}', lambda_theo, lambda_theo);
exp_fit_eq = sprintf('拟合: f(x) = %.3f e^{-%.3f x}', exp_p_fit(1), exp_p_fit(1));
exp_r2_text = sprintf('R² = %.4f', exp_r2);
% 在图片中标注公式（归一化坐标，避免随数据缩放）
text(0.05, 0.9, {exp_theo_eq, exp_fit_eq, exp_r2_text}, 'Units', 'normalized', ...
    'FontSize', 9, 'VerticalAlignment', 'top', 'BackgroundColor', 'white');
% 美化
title(sprintf('指数分布（N=%d）', N), 'FontSize', 12);
xlabel('随机数值', 'FontSize', 10);
ylabel('概率密度', 'FontSize', 10);
legend('Location', 'best');
grid on;
hold off;

% ---------- 子图2：均匀分布 ----------
subplot(3,1,2);
% 绘制直方图
histogram(unif_rand, num_bins, 'Normalization', 'pdf', 'EdgeColor', 'none', 'FaceColor', [0.8 1 0.8]);
hold on;
% 生成曲线x轴
unif_x = linspace(unif_a-1, unif_b+1, sample_points);
% 绘制拟合曲线
unif_y_fit_curve = unif_fit_fun(unif_p_fit, unif_x);
plot(unif_x, unif_y_fit_curve, 'r-', 'LineWidth', 2, 'DisplayName', '拟合曲线');
% 绘制理论曲线
unif_y_theo = (unif_x >= unif_a & unif_x <= unif_b) .* (1 / (unif_b - unif_a));
plot(unif_x, unif_y_theo, 'k--', 'LineWidth', 1.5, 'DisplayName', '理论曲线');
% 构建公式文本
unif_theo_eq = sprintf('理论: f(x) = %.3f（%.3f ≤ x ≤ %.3f）', 1/(unif_b-unif_a), unif_a, unif_b);
unif_fit_eq = sprintf('拟合: f(x) = %.3f（%.3f ≤ x ≤ %.3f）', 1/(unif_p_fit(2)-unif_p_fit(1)), unif_p_fit(1), unif_p_fit(2));
unif_r2_text = sprintf('R² = %.4f', unif_r2);
% 标注公式
text(0.05, 0.9, {unif_theo_eq, unif_fit_eq, unif_r2_text}, 'Units', 'normalized', ...
    'FontSize', 9, 'VerticalAlignment', 'top', 'BackgroundColor', 'white');
% 美化
title(sprintf('均匀分布（N=%d）', N), 'FontSize', 12);
xlabel('随机数值', 'FontSize', 10);
ylabel('概率密度', 'FontSize', 10);
legend('Location', 'best');
grid on;
hold off;

% ---------- 子图3：幂律分布 ----------
subplot(3,1,3);
% 绘制直方图
histogram(power_rand, num_bins, 'Normalization', 'pdf', 'EdgeColor', 'none', 'FaceColor', [1 0.8 0.8]);
hold on;
% 生成曲线x轴
power_x = linspace(power_xmin_theo, max(power_rand), sample_points);
% 绘制拟合曲线
power_y_fit_curve = power_fit_fun(power_p_fit, power_x);
plot(power_x, power_y_fit_curve, 'r-', 'LineWidth', 2, 'DisplayName', '拟合曲线');
% 绘制理论曲线
power_y_theo = (power_alpha - 1) * power_xmin_theo^(power_alpha - 1) ./ (power_x .^ power_alpha);
plot(power_x, power_y_theo, 'k--', 'LineWidth', 1.5, 'DisplayName', '理论曲线');
% 构建公式文本
power_theo_coeff = (power_alpha - 1) * power_xmin_theo^(power_alpha - 1);
power_theo_eq = sprintf('理论: f(x) = %.3f / x^%.1f（x ≥ %.3f）', power_theo_coeff, power_alpha, power_xmin_theo);
power_fit_coeff = (power_p_fit(1) - 1) * power_p_fit(2)^(power_p_fit(1) - 1);
power_fit_eq = sprintf('拟合: f(x) = %.3f / x^%.3f（x ≥ %.3f）', power_fit_coeff, power_p_fit(1), power_p_fit(2));
power_r2_text = sprintf('R² = %.4f', power_r2);
% 标注公式
text(0.05, 0.9, {power_theo_eq, power_fit_eq, power_r2_text}, 'Units', 'normalized', ...
    'FontSize', 9, 'VerticalAlignment', 'top', 'BackgroundColor', 'white');
% 美化
title(sprintf('幂律分布（N=%d）', N), 'FontSize', 12);
xlabel('随机数值', 'FontSize', 10);
ylabel('概率密度', 'FontSize', 10);
legend('Location', 'best');
grid on;
hold off;