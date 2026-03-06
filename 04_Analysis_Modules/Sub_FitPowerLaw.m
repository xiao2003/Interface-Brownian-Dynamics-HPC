function [alpha_fit, xmin_fit] = Sub_FitPowerLaw(data)
% Sub_FitPowerLaw - 幂律分布MLE拟合（最大似然估计）
% 输入：
%   data - 幂律分布样本数据（一维向量）
% 输出：
%   alpha_fit - 拟合的幂律指数α
%   xmin_fit - 拟合的最小阈值xmin

% 步骤1：去除非正数（幂律分布定义域x>0）
data = data(data > 0);
if isempty(data)
    alpha_fit = NaN;
    xmin_fit = NaN;
    warning('输入数据无正数，无法拟合幂律分布');
    return;
end

% 步骤2：MLE拟合xmin（简化版：取数据25%分位数，也可遍历优化）
xmin_fit = quantile(data, 0.25); % 避免极端值影响，用25%分位数作为xmin
data_filtered = data(data >= xmin_fit); % 仅保留x≥xmin的样本

% 步骤3：MLE拟合alpha
n = length(data_filtered);
alpha_fit = 1 + n / sum(log(data_filtered / xmin_fit));

% 输出拟合结果
fprintf('拟合结果：xmin=%.6f，alpha=%.4f\n', xmin_fit, alpha_fit);
end