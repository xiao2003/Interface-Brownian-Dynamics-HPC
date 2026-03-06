% powerlawtest.m - 修复维度不一致错误 + 对比alpha=-2.5/2.5幂律分布
clear; clc; close all;

%% 1. 核心参数定义
alpha_error = -2.5;    % 非有效幂律输入（仅数值计算，无幂律意义）
alpha_correct = 2.5;   % 有效幂律输入（对应x^-2.5分布）
meanValue = 0.01;      % 目标均值
N = 1e6;              % 样本量

%% 2. 生成幂律分布数据
PN_error = Sub_GeneratePowerLawWithMean(alpha_error, meanValue, N);
PN_correct = Sub_GeneratePowerLawWithMean(alpha_correct, meanValue, N);

%% 3. 计算均值和理论xmin并打印
mean_error = mean(PN_error);
mean_correct = mean(PN_correct);
xmin_error = meanValue * (alpha_error - 2) / (alpha_error - 1);
xmin_correct = meanValue * (alpha_correct - 2) / (alpha_correct - 1);

fprintf('alpha=%.1f的均值：%.6f\n', alpha_error, mean_error);
fprintf('alpha=%.1f的均值：%.6f\n', alpha_correct, mean_correct);
fprintf('alpha=%.1f的理论xmin：%.6f | alpha=%.1f的理论xmin：%.6f\n',...
    alpha_error, xmin_error, alpha_correct, xmin_correct);

%% 4. 绘制对比直方图（统一bin边界，避免维度不一致）
% 步骤1：统一bin边界（基于两个数据集的范围，生成等宽bin）
x_min_all = min([PN_error; PN_correct]);
x_max_all = max([PN_error; PN_correct]);
bin_width = 0.0005;                  % 统一bin宽度
bins = x_min_all:bin_width:x_max_all;% 生成统一的bin边界

% 步骤2：绘制双直方图（归一化到PDF）
figure('Position', [100, 100, 800, 500]); hold on; grid on;

% alpha=-2.5 直方图（橙色，不透明）
histogram(PN_error, bins, 'Normalization', 'pdf', ...
    'FaceColor', [1, 0.5, 0], 'FaceAlpha', 1, 'EdgeColor', 'none', ...  % FaceAlpha改为1（不透明）
    'DisplayName', sprintf('alpha=%.1f（非有效幂律）', alpha_error));

% alpha=2.5 直方图（蓝色，不透明）
histogram(PN_correct, bins, 'Normalization', 'pdf', ...
    'FaceColor', [0, 0.5, 1], 'FaceAlpha', 1, 'EdgeColor', 'none', ...  % FaceAlpha改为1（不透明）
    'DisplayName', sprintf('alpha=%.1f（有效幂律x^{-2.5}）', alpha_correct));

%% 5. 绘制alpha=2.5的理论PDF曲线（仅有效曲线）
x_correct = linspace(xmin_correct, x_max_all, 200);
pdf_correct = (alpha_correct - 1)/xmin_correct .* (x_correct/xmin_correct).^(-alpha_correct);
plot(x_correct, pdf_correct, 'b-', 'LineWidth', 2, ...
    'DisplayName', 'alpha=2.5 理论PDF');

%% 6. 修复max_hist_y计算（避免维度不一致）
% 先分别计算两个直方图的最大概率密度，再取整体最大值
hc_error = histcounts(PN_error, bins, 'Normalization', 'pdf');
hc_correct = histcounts(PN_correct, bins, 'Normalization', 'pdf');
max_hist_y = max([max(hc_error), max(hc_correct)]); % 分别取max再合并
max_pdf_y = max(pdf_correct);
ylim_top = max([max_hist_y, max_pdf_y]) * 1.1;

%% 7. 坐标轴与标注设置
xlim([x_min_all, x_max_all * 1.05]);
ylim([0, ylim_top]); % 确保是[0, 正数]的递增向量
xlabel('数值 x', 'FontSize', 12);
ylabel('概率密度 PDF', 'FontSize', 12);
title('alpha=-2.5 vs alpha=2.5 幂律分布对比（均值目标=0.01）', 'FontSize', 14);
legend('Location', 'best', 'FontSize', 10);